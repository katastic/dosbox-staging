/*
 *  Copyright (C) 2002-2021  The DOSBox Team
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with this program; if not, write to the Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */


#include <stdlib.h>
#include <string.h>
#include "dosbox.h"
#include "mem.h"
#include "mem_host.h"
#include "vga.h"
#include "paging.h"
#include "pic.h"
#include "inout.h"
#include "setup.h"



//https://stackoverflow.com/questions/10132706/retrieve-byte-from-32-bit-integer-using-bitwise-operators
int getByte(int x, int n) {
  return (x >> 8*n) & 0xFF;
}

#ifndef C_VGARAM_CHECKED
#define C_VGARAM_CHECKED 1
#endif

#if C_VGARAM_CHECKED
// Checked linear offset
#define CHECKED(v) ((v)&(vga.vmemwrap-1))
// Checked planar offset (latched access)
#define CHECKED2(v) ((v)&((vga.vmemwrap>>2)-1))
#else
#define CHECKED(v) (v)
#define CHECKED2(v) (v)
#endif

#define CHECKED3(v) ((v)&(vga.vmemwrap-1))
#define CHECKED4(v) ((v)&((vga.vmemwrap>>2)-1))


#ifdef VGA_KEEP_CHANGES
#define MEM_CHANGED( _MEM ) vga.changes.map[ (_MEM) >> VGA_CHANGE_SHIFT ] |= vga.changes.writeMask;
//#define MEM_CHANGED( _MEM ) vga.changes.map[ (_MEM) >> VGA_CHANGE_SHIFT ] = 1;
#else
#define MEM_CHANGED( _MEM ) 
#endif

#define TANDY_VIDBASE(_X_)  &MemBase[ 0x80000 + (_X_)]

void VGA_MapMMIO(void);
//Nice one from DosEmu
inline static uint32_t RasterOp(uint32_t input,uint32_t mask) {
	switch (vga.config.raster_op) {
	case 0x00:	/* None */
		return (input & mask) | (vga.latch.d & ~mask);
	case 0x01:	/* AND */
		return (input | ~mask) & vga.latch.d;
	case 0x02:	/* OR */
		return (input & mask) | vga.latch.d;
	case 0x03:	/* XOR */
		return (input & mask) ^ vga.latch.d;
	};
	return 0;
}

inline static uint32_t ModeOperation(uint8_t val) {
	uint32_t full;
	switch (vga.config.write_mode) {
	case 0x00:
		// Write Mode 0: In this mode, the host data is first rotated as per the Rotate Count field, then the Enable Set/Reset mechanism selects data from this or the Set/Reset field. Then the selected Logical Operation is performed on the resulting data and the data in the latch register. Then the Bit Mask field is used to select which bits come from the resulting data and which come from the latch register. Finally, only the bit planes enabled by the Memory Plane Write Enable field are written to memory. 
		val=((val >> vga.config.data_rotate) | (val << (8-vga.config.data_rotate)));
		full=ExpandTable[val];
		full=(full & vga.config.full_not_enable_set_reset) | vga.config.full_enable_and_set_reset; 
		full=RasterOp(full,vga.config.full_bit_mask);
		break;
	case 0x01:
		// Write Mode 1: In this mode, data is transferred directly from the 32 bit latch register to display memory, affected only by the Memory Plane Write Enable field. The host data is not used in this mode. 
		full=vga.latch.d;
		break;
	case 0x02:
		//Write Mode 2: In this mode, the bits 3-0 of the host data are replicated across all 8 bits of their respective planes. Then the selected Logical Operation is performed on the resulting data and the data in the latch register. Then the Bit Mask field is used to select which bits come from the resulting data and which come from the latch register. Finally, only the bit planes enabled by the Memory Plane Write Enable field are written to memory. 
		full=RasterOp(FillTable[val&0xF],vga.config.full_bit_mask);
		break;
	case 0x03:
		// Write Mode 3: In this mode, the data in the Set/Reset field is used as if the Enable Set/Reset field were set to 1111b. Then the host data is first rotated as per the Rotate Count field, then logical ANDed with the value of the Bit Mask field. The resulting value is used on the data obtained from the Set/Reset field in the same way that the Bit Mask field would ordinarily be used. to select which bits come from the expansion of the Set/Reset field and which come from the latch register. Finally, only the bit planes enabled by the Memory Plane Write Enable field are written to memory.
		val=((val >> vga.config.data_rotate) | (val << (8-vga.config.data_rotate)));
		full=RasterOp(vga.config.full_set_reset,ExpandTable[val] & vga.config.full_bit_mask);
		break;
	default:
		LOG(LOG_VGAMISC,LOG_NORMAL)("VGA:Unsupported write mode %d",vga.config.write_mode);
		full=0;
		break;
	}
	return full;
}

/* Gonna assume that whoever maps vga memory, maps it on 32/64kb boundary */

#define VGA_PAGES		(128/4)
#define VGA_PAGE_A0		(0xA0000/4096)
#define VGA_PAGE_B0		(0xB0000/4096)
#define VGA_PAGE_B8		(0xB8000/4096)

static struct {
	Bitu base, mask;
} vgapages;
	
class VGA_UnchainedRead_Handler : public PageHandler {
public:
	uint8_t readHandler(PhysPt start)
	{
		vga.latch.d=((uint32_t*)vga.mem.linear)[start];
		switch (vga.config.read_mode) {
		case 0:
			return (vga.latch.b[vga.config.read_map_select]);
		case 1:
			VGA_Latch templatch;
			templatch.d=(vga.latch.d &	FillTable[vga.config.color_dont_care]) ^ FillTable[vga.config.color_compare & vga.config.color_dont_care];
			return (uint8_t)~(templatch.b[0] | templatch.b[1] | templatch.b[2] | templatch.b[3]);
		}
		// printf("hello90\n"); READ
		return 0;
	}

public:
	uint8_t readb(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED2(addr);
		// printf("hello91\n"); REAd
		return readHandler(addr);
	}
	
	uint16_t readw(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED2(addr);
		// printf("hello92\n"); READ
		return static_cast<uint16_t>((readHandler(addr + 0) << 0) |
		                             (readHandler(addr + 1) << 8));
	}

	uint32_t readd(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED2(addr);
		// printf("hello93\n"); READ
		return static_cast<uint32_t>((readHandler(addr + 0) << 0) |
		                             (readHandler(addr + 1) << 8) |
		                             (readHandler(addr + 2) << 16) |
		                             (readHandler(addr + 3) << 24));
	}
};

class VGA_ChainedEGA_Handler final : public PageHandler {
public:
	uint8_t readHandler(PhysPt addr) { return vga.mem.linear[addr]; }
	void writeHandler(PhysPt start, uint8_t val) {
		ModeOperation(val);
		/* Update video memory and the pixel buffer */
		VGA_Latch pixels;
		vga.mem.linear[start] = val;
		start >>= 2;
		pixels.d=((uint32_t*)vga.mem.linear)[start];

		uint8_t * write_pixels=&vga.fastmem[start<<3];

		uint32_t colors0_3, colors4_7;
		VGA_Latch temp;temp.d=(pixels.d>>4) & 0x0f0f0f0f;
		colors0_3 = 
			Expand16Table[0][temp.b[0]] |
			Expand16Table[1][temp.b[1]] |
			Expand16Table[2][temp.b[2]] |
			Expand16Table[3][temp.b[3]];
		*(uint32_t *)write_pixels=colors0_3;
		temp.d=pixels.d & 0x0f0f0f0f;
		colors4_7 = 
			Expand16Table[0][temp.b[0]] |
			Expand16Table[1][temp.b[1]] |
			Expand16Table[2][temp.b[2]] |
			Expand16Table[3][temp.b[3]];
		*(uint32_t *)(write_pixels+4)=colors4_7;
		printf("hello6\n");
	}
public:	
	VGA_ChainedEGA_Handler()  {
		flags=PFLAG_NOCODE;
	}

	void writeb(PhysPt addr, uint8_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED(addr);
		MEM_CHANGED( addr << 3);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		printf("hello7\n");
	}

	void writew(PhysPt addr, uint16_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED(addr);
		MEM_CHANGED( addr << 3);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		printf("hello8\n");
	}

	void writed(PhysPt addr, uint32_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED(addr);
		MEM_CHANGED( addr << 3);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		writeHandler(addr+2,(uint8_t)(val >> 16));
		writeHandler(addr+3,(uint8_t)(val >> 24));
		printf("hello9\n");
	}

	uint8_t readb(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		return readHandler(addr);
	}

	uint16_t readw(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		return static_cast<uint16_t>((readHandler(addr + 0) << 0) |
		                             (readHandler(addr + 1) << 8));
	}

	uint32_t readd(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		return static_cast<uint32_t>((readHandler(addr + 0) << 0) |
		                             (readHandler(addr + 1) << 8) |
		                             (readHandler(addr + 2) << 16) |
		                             (readHandler(addr + 3) << 24));
	}
};

class VGA_UnchainedEGA_Handler : public VGA_UnchainedRead_Handler {
public:
	void writeHandler(PhysPt start, uint8_t val) { // so far EGA appears to be a full mask every time but maybe it's a different register/variable and we're snooping the VGA only one.
		uint32_t data=ModeOperation(val);
		/* Update video memory and the pixel buffer */
		VGA_Latch pixels;
		pixels.d=((uint32_t*)vga.mem.linear)[start];
		pixels.d&=vga.config.full_not_map_mask;
		pixels.d|=(data & vga.config.full_map_mask);
		((uint32_t*)vga.mem.linear)[start]=pixels.d;
		uint8_t * write_pixels=&vga.fastmem[start<<3];

		printf("start:%x start<<3:%x full_map_mask:%8x  @ %d,%d\n", start, start<<3, vga.config.full_map_mask, start % 320, start / 320);

		uint32_t colors0_3, colors4_7;
		VGA_Latch temp;
		temp.d=(pixels.d>>4) & 0x0f0f0f0f;
		colors0_3 = 
			Expand16Table[0][temp.b[0]] |
			Expand16Table[1][temp.b[1]] |
			Expand16Table[2][temp.b[2]] |
			Expand16Table[3][temp.b[3]];
		*(uint32_t *)write_pixels=colors0_3;
			
		const int NUM_BYTES = 4;
		printf("%d,%s,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%u\n", 
			KAT_CURRENT_FRAME, "hello40A", MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			start, NUM_BYTES, 
			colors0_3 & 0b00000000000000000000000011111111,
			colors0_3 & 0b00000000000000001111111100000000 >> 8,
			colors0_3 & 0b00000000111111110000000000000000 >> 16,
			colors0_3 & 0b11111111000000000000000000000000 >> 24,
			vga.config.full_map_mask
			); // we "should" only need temp.b[0] for first pixel, etc. I think the expand table just moves it.
					
		temp.d=pixels.d & 0x0f0f0f0f;
		colors4_7 = 
			Expand16Table[0][temp.b[0]] |
			Expand16Table[1][temp.b[1]] |
			Expand16Table[2][temp.b[2]] |
			Expand16Table[3][temp.b[3]];
		*(uint32_t *)(write_pixels+4)=colors4_7;
		
		printf("%d,%s,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%u\n", 
			KAT_CURRENT_FRAME, "hello40B", MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			start+4, NUM_BYTES,
			colors4_7 & 0b00000000000000000000000011111111,
			colors4_7 & 0b00000000000000001111111100000000 >> 8,
			colors4_7 & 0b00000000111111110000000000000000 >> 16,
			colors4_7 & 0b11111111000000000000000000000000 >> 24,
			vga.config.full_map_mask
			);

	}
public:	
	VGA_UnchainedEGA_Handler()  {	// commander keen 1, EGA
		flags=PFLAG_NOCODE;
	}

	void writeb(PhysPt addr, uint8_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED2(addr);
		MEM_CHANGED( addr << 3);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		/*
		const int NUM_BYTES = 1;
		
			should be covered by hello40A/B, removed to reduce log spam
			
			printf("%d,hello30b,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES,(uint8_t)(val >> 0), -1,-1,-1);
			*/
	}

	void writew(PhysPt addr, uint16_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED2(addr);
		MEM_CHANGED( addr << 3);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		/*
		 * should be covered by hello40A/B, removed to reduce log spam
		const int NUM_BYTES = 2;
		printf("%d,hello31w,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, (uint8_t)(val >> 0), (uint8_t)(val >> 8),-1,-1);
			*/
	}

	void writed(PhysPt addr, uint32_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED2(addr);
		MEM_CHANGED( addr << 3);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		writeHandler(addr+2,(uint8_t)(val >> 16));
		writeHandler(addr+3,(uint8_t)(val >> 24));
		const int NUM_BYTES = 1;
		printf("%d,hello32d,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, (uint8_t)(val >> 0), (uint8_t)(val >> 8), (uint8_t)(val >> 16), (uint8_t)(val >> 24));
	}
};

//Slighly unusual version, will directly write 8,16,32 bits values
class VGA_ChainedVGA_Handler final : public PageHandler {
public:
	VGA_ChainedVGA_Handler()  {
		flags=PFLAG_NOCODE;
	}
	static inline uint8_t *ToLinear(PhysPt addr)
	{
		return &vga.mem.linear[((addr & ~3) << 2) + (addr & 3)];
	}

	static inline uint8_t readHandler_byte(PhysPt addr)
	{
		return host_readb(ToLinear(addr));
	}
	
	static inline uint16_t readHandler_word(PhysPt addr)
	{
		return host_readw(ToLinear(addr));
	}
	
	static inline uint32_t readHandler_dword(PhysPt addr)
	{
		return host_readd(ToLinear(addr));
	}

	template <typename func_t, typename val_t>
	static inline void WriteCache_template(func_t host_write, PhysPt addr, val_t val)
	{
		host_write(&vga.fastmem[addr], val);
		if (GCC_UNLIKELY(addr < 320)) {
			// And replicate the first line
			host_write(&vga.fastmem[addr + 64 * 1024], val);
		}
	}
	
	static inline void writeCache_byte(PhysPt addr, uint8_t val)
	{

//	printf("hello60\n");
		WriteCache_template(host_writeb, addr, val);
	}
	
	static inline void writeCache_word(PhysPt addr, uint16_t val)
	{
//	printf("hello61\n");
		WriteCache_template(host_writew, addr, val);
	}
	
	static inline void writeCache_dword(PhysPt addr, uint32_t val)
	{
//	printf("hello62\n");
		WriteCache_template(host_writed, addr, val);
	}

	// No need to check for compatible chains here, this one is only enabled
	// if that bit is set
	static inline void writeHandler_byte(PhysPt addr, uint8_t val)
	{
//	printf("hello63\n");
		host_writeb(ToLinear(addr), val);
	}
	
	static inline void writeHandler_word(PhysPt addr, uint16_t val)
	{
//	printf("hello64\n");
		host_writew(ToLinear(addr), val);
	}
	
	static inline void writeHandler_dword(PhysPt addr, uint32_t val)
	{
//	printf("hello65\n");
		host_writed(ToLinear(addr), val);
	}

	uint8_t readb(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		return readHandler_byte(addr);
	}

	uint16_t readw(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		if (GCC_UNLIKELY(addr & 1)) {
			return static_cast<uint16_t>(
			        (readHandler_byte(addr + 0) << 0) |
			        (readHandler_byte(addr + 1) << 8));
		} else
			return readHandler_word(addr);
	}

	uint32_t readd(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		if (GCC_UNLIKELY(addr & 3)) {
			return static_cast<uint32_t>(
			        (readHandler_byte(addr + 0) << 0) |
			        (readHandler_byte(addr + 1) << 8) |
			        (readHandler_byte(addr + 2) << 16) |
			        (readHandler_byte(addr + 3) << 24));

		} else
			return readHandler_dword(addr);
	}

	void writeb(PhysPt addr, uint8_t val)
	{
		printf("a%d\n", addr);
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		printf("b%d\n", addr);
		addr += vga.svga.bank_write_full;
		printf("c%d\n", addr);
		addr = CHECKED(addr);
		printf("d%d\n", addr);
		MEM_CHANGED( addr );
		printf("e%d\n", addr);
		writeHandler_byte(addr, val);
		printf("f%d\n", addr);
		writeCache_byte(addr, val);
		printf("g%d\n", addr);
		const int NUM_BYTES = 1;
		printf("%d,hello10b,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, getByte(val, 0), getByte(val, 1),-1,-1);
	}

	void writew(PhysPt addr, uint16_t val)
	{
//		printf("addr0 = %d ", addr);
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
//		printf("addr1 = %d ", addr);
		addr += vga.svga.bank_write_full;
//		printf("addr2 = %d ", addr);
		addr = CHECKED(addr);
//		printf("addr3 = %d\n", addr);
		MEM_CHANGED( addr );
				
//		MEM_CHANGED( addr + 1);
		if (GCC_UNLIKELY(addr & 1)) {
			writeHandler_byte(addr + 0, val >> 0);
			writeHandler_byte(addr + 1, val >> 8);
		} else {
			writeHandler_word(addr, val);
		}
		writeCache_word(addr, val);

		const int NUM_BYTES = 2;
		printf("%d,hello11w,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, getByte(val, 0), getByte(val, 1),-1,-1);
		
		// VGA 320x200x8, Nite Raid.
	}

	void writed(PhysPt addr, uint32_t val)
	{
			addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED(addr);
		MEM_CHANGED( addr );
//		MEM_CHANGED( addr + 3);
		if (GCC_UNLIKELY(addr & 3)) {
			writeHandler_byte(addr + 0, val >> 0);
			writeHandler_byte(addr + 1, val >> 8);
			writeHandler_byte(addr + 2, val >> 16);
			writeHandler_byte(addr + 3, val >> 24);
		} else {
			writeHandler_dword(addr, val);
		}
		writeCache_dword(addr, val);

		const int NUM_BYTES = 4;
		printf("%d,hello12d,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, getByte(val, 0), getByte(val, 1), getByte(val, 2), getByte(val, 3));

	}
};

// THIS SHOULD BE modex right? and various other unchained VGA
class VGA_UnchainedVGA_Handler final : public VGA_UnchainedRead_Handler {
public:
	void writeHandler( PhysPt addr, uint8_t val ) {
		uint8_t oldval = val;
		uint32_t data=ModeOperation(val);
		VGA_Latch pixels;
		pixels.d=((uint32_t*)vga.mem.linear)[addr];
		pixels.d&=vga.config.full_not_map_mask;
		pixels.d|=(data & vga.config.full_map_mask);
		((uint32_t*)vga.mem.linear)[addr]=pixels.d;
//		if(vga.config.compatible_chain4)
//			((uint32_t*)vga.mem.linear)[CHECKED2(addr+64*1024)]=pixels.d;

		// I think MASK ENDIANNESS/ORDER IS FLIPPED
		// 		[below] val:252 data[]=252,252,252,252 pixels.d=252,0,0,0 notmask:FFFFFF00 mask000000FF

		printf("[below] val:%d data[]=%d,%d,%d,%d pixels.d=%d,%d,%d,%d notmask:%08X mask%08X\n", oldval, getByte(data, 0), getByte(data, 1), getByte(data, 2), getByte(data, 3), getByte(pixels.d, 0), getByte(pixels.d, 1), getByte(pixels.d, 2), getByte(pixels.d, 3), vga.config.full_not_map_mask, vga.config.full_map_mask);
		const int NUM_BYTES = 1;
		//printf("%d,hello55A,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%u\n", 
//			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			//addr, NUM_BYTES,val,-1,-1,-1, vga.config.full_map_mask); //note unsigned at end
		printf("%d,%s,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%u\n", 
			KAT_CURRENT_FRAME, "hello55A", MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, 
			val,
			-1,
			-1,
			-1,
			vga.config.full_map_mask
			); 
	}
public:
	VGA_UnchainedVGA_Handler()  {
		flags=PFLAG_NOCODE;
	}

	void writeb(PhysPt addr, uint8_t val) // -->MODE X/Y <---, dosbox, exmem.c putpixel AS WELL AS TEXT MODE.
	{
		printf("a %d\n", addr);
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		printf("b %d\n", addr);
		addr += vga.svga.bank_write_full;
		printf("c %d\n", addr);
		addr = CHECKED2(addr);
		printf("d %d\n", addr);
		MEM_CHANGED( addr << 2 );
		printf("e %d\n", addr);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		printf("f %d\n", addr);
		const int NUM_BYTES = 1;
		int tempAddr = addr;
//		if(vga.config.full_map_mask == 0x000000FF)tempAddr += 0; // note sure this is right
//		if(vga.config.full_map_mask == 0x0000FF00)tempAddr += 1;
//		if(vga.config.full_map_mask == 0x00FF0000)tempAddr += 2;
//		if(vga.config.full_map_mask == 0xFF000000)tempAddr += 3;
		printf("%d,hello13b,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%u\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			tempAddr, NUM_BYTES, getByte(val, 0), -1, -1, -1, vga.config.full_map_mask);
		//printf("    %d %d %d %d %d\n", vga.config.chained, vga.config.compatible_chain4, vga.config.addr_shift, vga.config.write_mode, vga.config.write_mode);
		// 0 1 0 0 0
	}

	void writew(PhysPt addr, uint16_t val)	// used in Wolf3D MODE X/Y
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED2(addr);
		MEM_CHANGED( addr << 2);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		const int NUM_BYTES = 2;
		printf("%d,hello14w,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%u\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, getByte(val, 0), getByte(val, 1), -1, -1, vga.config.full_map_mask);
		}

	void writed(PhysPt addr, uint32_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED2(addr);
		MEM_CHANGED( addr << 2);
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		writeHandler(addr+2,(uint8_t)(val >> 16));
		writeHandler(addr+3,(uint8_t)(val >> 24));
		const int NUM_BYTES = 4;
		printf("%d,hello15d,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%u\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, getByte(val, 0), getByte(val, 1), getByte(val, 2), getByte(val, 3), vga.config.full_map_mask);
	}
};

class VGA_TEXT_PageHandler final : public PageHandler {
public:
	VGA_TEXT_PageHandler() {
		flags=PFLAG_NOCODE;
	}

	uint8_t readb(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		switch(vga.gfx.read_map_select) {
		case 0: // character index
			return vga.mem.linear[CHECKED3(vga.svga.bank_read_full+addr)];
		case 1: // character attribute
			return vga.mem.linear[CHECKED3(vga.svga.bank_read_full+addr+1)];
		case 2: // font map
			return vga.draw.font[addr];
		default: // 3=unused, but still RAM that could save values
			return 0;
		}
	}

	void writeb(PhysPt addr, uint8_t val) // KAT we don't care (ATM at least) about non-character writes to color or attribute pages. but snooping only the final index didn't seem to show results.
	{
		unsigned int mode = -1;
			addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		
		if (GCC_LIKELY(vga.seq.map_mask == 0x4)) {
			vga.draw.font[addr] = val;
			mode = 0; // 'normal', so far all hits are here
		} else {
			if (vga.seq.map_mask & 0x4) // font map
				{vga.draw.font[addr] = val; mode = 1;} //(f)ont, none so far
			if (vga.seq.map_mask & 0x2) // character attribute
				{vga.draw.font[addr] = val; mode = 2; //(a)ttribute, none so far
				vga.mem.linear[CHECKED3(vga.svga.bank_read_full +
				                        addr + 1)] = val;}
			if (vga.seq.map_mask & 0x1) // character index				
				{vga.draw.font[addr] = val; mode = 3; //(i)ndex, none so far
				vga.mem.linear[CHECKED3(vga.svga.bank_read_full + addr)] = val;
				}
		}		
		const int NUM_BYTES = 1;
		printf("%d,hello16b,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d\n", 
			KAT_CURRENT_FRAME, MODE_NUMBER, MODE_W, MODE_H, MODE_COLORS, MODE_NAME, 
			addr, NUM_BYTES, val, -1, -1,mode);
			// WANNING, we're tossing vgapages.mask, and mode on the end!
		// printf("vgapages.mask=%lu\n", vgapages.mask);
		// in the case of Keen1, ALL MASKS = 65535 (0xffff)

	}
};

class VGA_Map_Handler final : public PageHandler {
public:
	VGA_Map_Handler() {
		flags=PFLAG_READABLE|PFLAG_WRITEABLE|PFLAG_NOCODE;
	}
	HostPt GetHostReadPt(Bitu phys_page) {
 		phys_page-=vgapages.base;
		return &vga.mem.linear[CHECKED3(vga.svga.bank_read_full+phys_page*4096)];
	}
	HostPt GetHostWritePt(Bitu phys_page) {
 		phys_page-=vgapages.base;
		return &vga.mem.linear[CHECKED3(vga.svga.bank_write_full+phys_page*4096)];
	}
};

class VGA_Changes_Handler final : public PageHandler {
public:
	VGA_Changes_Handler() {
		flags=PFLAG_NOCODE;
	}
	uint8_t readb(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		return host_readb(&vga.mem.linear[addr]);
	}

	uint16_t readw(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		return host_readw_at(vga.mem.linear, addr);
	}

	uint32_t readd(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_read_full;
		addr = CHECKED(addr);
		return host_readd_at(vga.mem.linear, addr);
	}

	void writeb(PhysPt addr, uint8_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED(addr);
		MEM_CHANGED( addr );
		host_writeb(&vga.mem.linear[addr], val);
		printf("hello4\n");
	}

	void writew(PhysPt addr, uint16_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED(addr);
		MEM_CHANGED(addr);
		host_writew_at(vga.mem.linear, addr, val);
		printf("hello5\n");
	}

	void writed(PhysPt addr, uint32_t val)
	{
		addr = PAGING_GetPhysicalAddress(addr) & vgapages.mask;
		addr += vga.svga.bank_write_full;
		addr = CHECKED(addr);
		MEM_CHANGED(addr);
		host_writed_at(vga.mem.linear, addr, val);
		printf("hello6\n");
	}
};

class VGA_LIN4_Handler final : public VGA_UnchainedEGA_Handler {
public:
	VGA_LIN4_Handler() {
		flags=PFLAG_NOCODE;
	}
	void writeb(PhysPt addr, uint8_t val)
	{
		addr = vga.svga.bank_write_full + (PAGING_GetPhysicalAddress(addr) & 0xffff);
		addr = CHECKED4(addr);
		MEM_CHANGED( addr << 3 );
		writeHandler(addr+0,(uint8_t)(val >> 0));
		printf("hello\n");
	}

	void writew(PhysPt addr, uint16_t val)
	{
		addr = vga.svga.bank_write_full + (PAGING_GetPhysicalAddress(addr) & 0xffff);
		addr = CHECKED4(addr);
		MEM_CHANGED( addr << 3 );
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		printf("hello2\n");
	}

	void writed(PhysPt addr, uint32_t val)
	{
		addr = vga.svga.bank_write_full + (PAGING_GetPhysicalAddress(addr) & 0xffff);
		addr = CHECKED4(addr);
		MEM_CHANGED( addr << 3 );
		writeHandler(addr+0,(uint8_t)(val >> 0));
		writeHandler(addr+1,(uint8_t)(val >> 8));
		writeHandler(addr+2,(uint8_t)(val >> 16));
		writeHandler(addr+3,(uint8_t)(val >> 24));
		printf("hello3\n");
	}

	uint8_t readb(PhysPt addr)
	{
		addr = vga.svga.bank_read_full + (PAGING_GetPhysicalAddress(addr) & 0xffff);
		addr = CHECKED4(addr);
		return readHandler(addr);
	}

	uint16_t readw(PhysPt addr)
	{
		addr = vga.svga.bank_read_full + (PAGING_GetPhysicalAddress(addr) & 0xffff);
		addr = CHECKED4(addr);
		return static_cast<uint16_t>((readHandler(addr + 0) << 0) |
		                             (readHandler(addr + 1) << 8));
	}

	uint32_t readd(PhysPt addr)
	{
		addr = vga.svga.bank_read_full + (PAGING_GetPhysicalAddress(addr) & 0xffff);
		addr = CHECKED4(addr);
		return static_cast<uint32_t>((readHandler(addr + 0) << 0) |
		                             (readHandler(addr + 1) << 8) |
		                             (readHandler(addr + 2) << 16) |
		                             (readHandler(addr + 3) << 24));
	}
};


class VGA_LFBChanges_Handler final : public PageHandler {
public:
	VGA_LFBChanges_Handler() {
		flags=PFLAG_NOCODE;
	}

	uint8_t readb(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) - vga.lfb.addr;
		addr = CHECKED(addr);
		return host_readb(&vga.mem.linear[addr]);
	}

	uint16_t readw(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) - vga.lfb.addr;
		addr = CHECKED(addr);
		return host_readw_at(vga.mem.linear, addr);
	}

	uint32_t readd(PhysPt addr)
	{
		addr = PAGING_GetPhysicalAddress(addr) - vga.lfb.addr;
		addr = CHECKED(addr);
		return host_readd_at(vga.mem.linear, addr);
	}

	void writeb(PhysPt addr, uint8_t val)
	{
	printf("hello18\n");
			addr = PAGING_GetPhysicalAddress(addr) - vga.lfb.addr;
		addr = CHECKED(addr);
		host_writeb(&vga.mem.linear[addr], val);
		MEM_CHANGED( addr );
	}

	void writew(PhysPt addr, uint16_t val)
	{
	printf("hello19\n");
		addr = PAGING_GetPhysicalAddress(addr) - vga.lfb.addr;
		addr = CHECKED(addr);
		host_writew_at(vga.mem.linear, addr, val);
		MEM_CHANGED( addr );
	}

	void writed(PhysPt addr, uint32_t val)
	{
	printf("hello20\n");
		addr = PAGING_GetPhysicalAddress(addr) - vga.lfb.addr;
		addr = CHECKED(addr);
		host_writed_at(vga.mem.linear, addr, val);
		MEM_CHANGED( addr );
	}
};

class VGA_LFB_Handler final : public PageHandler {
public:
	VGA_LFB_Handler() {
		flags=PFLAG_READABLE|PFLAG_WRITEABLE|PFLAG_NOCODE;
	}
	HostPt GetHostReadPt( Bitu phys_page ) {
		phys_page -= vga.lfb.page;
		return &vga.mem.linear[CHECKED3(phys_page * 4096)];
	}
	HostPt GetHostWritePt( Bitu phys_page ) {
		return GetHostReadPt( phys_page );
	}
};

extern void XGA_Write(io_port_t port, io_val_t value, io_width_t width);
extern uint32_t XGA_Read(io_port_t port, io_width_t width);

class VGA_MMIO_Handler final : public PageHandler {
public:
	VGA_MMIO_Handler() {
		flags=PFLAG_NOCODE;
	}

	void writeb(PhysPt addr, uint8_t val)
	{
	printf("hello24\n");
		Bitu port = PAGING_GetPhysicalAddress(addr) & 0xffff;
		XGA_Write(port, val, io_width_t::byte);
	}

	void writew(PhysPt addr, uint16_t val)
	{
	printf("hello25\n");
		Bitu port = PAGING_GetPhysicalAddress(addr) & 0xffff;
		XGA_Write(port, val, io_width_t::word);
	}

	void writed(PhysPt addr, uint32_t val)
	{
	printf("hello26\n");
		Bitu port = PAGING_GetPhysicalAddress(addr) & 0xffff;
		XGA_Write(port, val, io_width_t::dword);
	}

	uint8_t readb(PhysPt addr)
	{
		Bitu port = PAGING_GetPhysicalAddress(addr) & 0xffff;
		return XGA_Read(port, io_width_t::byte);
	}

	uint16_t readw(PhysPt addr)
	{
		Bitu port = PAGING_GetPhysicalAddress(addr) & 0xffff;
		return XGA_Read(port, io_width_t::word);
	}

	uint32_t readd(PhysPt addr)
	{
		Bitu port = PAGING_GetPhysicalAddress(addr) & 0xffff;
		return XGA_Read(port, io_width_t::dword);
	}
};

class VGA_TANDY_PageHandler final : public PageHandler {
public:
	VGA_TANDY_PageHandler() {
		flags=PFLAG_READABLE|PFLAG_WRITEABLE;
//			|PFLAG_NOCODE;
	}
	HostPt GetHostReadPt(Bitu phys_page) {
		// Odd banks are limited to 16kB and repeated
		if (vga.tandy.mem_bank & 1) 
			phys_page&=0x03;
		else 
			phys_page&=0x07;
		return vga.tandy.mem_base + (phys_page * 4096);
	}
	HostPt GetHostWritePt(Bitu phys_page) {
		return GetHostReadPt( phys_page );
	}
};


class VGA_PCJR_Handler final : public PageHandler {
public:
	VGA_PCJR_Handler() {
		flags=PFLAG_READABLE|PFLAG_WRITEABLE;
	}
	HostPt GetHostReadPt(Bitu phys_page) {
		phys_page-=0xb8;
		// The 16kB map area is repeated in the 32kB range
		// On CGA CPU A14 is not decoded so it repeats there too
		phys_page&=0x03;
		return vga.tandy.mem_base + (phys_page * 4096);
	}
	HostPt GetHostWritePt(Bitu phys_page) {
		return GetHostReadPt( phys_page );
	}
};

class VGA_HERC_Handler final : public PageHandler {
public:
	VGA_HERC_Handler() {
		flags=PFLAG_READABLE|PFLAG_WRITEABLE;
	}
	HostPt GetHostReadPt(Bitu /*phys_page*/) {
		// The 4kB map area is repeated in the 32kB range
		return &vga.mem.linear[0];
	}
	HostPt GetHostWritePt(Bitu phys_page) {
		return GetHostReadPt( phys_page );
	}
};

class VGA_Empty_Handler final : public PageHandler {
public:
	VGA_Empty_Handler() {
		flags=PFLAG_NOCODE;
	}
	uint8_t readb(PhysPt /*addr*/)
	{
		//		LOG(LOG_VGA, LOG_NORMAL ) ( "Read from empty
		//memory space at %x", addr );
		return 0xff;
	}

	void writeb(PhysPt /*addr*/, uint8_t /*val*/)
	{
		//		LOG(LOG_VGA, LOG_NORMAL ) ( "Write %x to empty
		//memory space at %x", val, addr );
	}
};

static struct vg {
	VGA_Map_Handler map = {};
	VGA_Changes_Handler changes = {};
	VGA_TEXT_PageHandler text = {};
	VGA_TANDY_PageHandler tandy = {};
	VGA_ChainedEGA_Handler cega = {};
	VGA_ChainedVGA_Handler cvga = {};
	VGA_UnchainedEGA_Handler uega = {};
	VGA_UnchainedVGA_Handler uvga = {};
	VGA_PCJR_Handler pcjr = {};
	VGA_HERC_Handler herc = {};
	VGA_LIN4_Handler lin4 = {};
	VGA_LFB_Handler lfb = {};
	VGA_LFBChanges_Handler lfbchanges = {};
	VGA_MMIO_Handler mmio = {};
	VGA_Empty_Handler empty = {};
} vgaph;

void VGA_ChangedBank(void) {
#ifndef VGA_LFB_MAPPED
	//If the mode is accurate than the correct mapper must have been installed already
	if ( vga.mode >= M_LIN4 && vga.mode <= M_LIN32 ) {
		return;
	}
#endif
	VGA_SetupHandlers();
}

void VGA_SetupHandlers(void) {
	vga.svga.bank_read_full = vga.svga.bank_read*vga.svga.bank_size;
	vga.svga.bank_write_full = vga.svga.bank_write*vga.svga.bank_size;

	PageHandler *newHandler;
	switch (machine) {
	case MCH_CGA:
	case MCH_PCJR:
		MEM_SetPageHandler( VGA_PAGE_A0, 16, &vgaph.empty );
		MEM_SetPageHandler( VGA_PAGE_B0, 8, &vgaph.empty );
		MEM_SetPageHandler( VGA_PAGE_B8, 8, &vgaph.pcjr );
		goto range_done;
	case MCH_HERC:
		MEM_SetPageHandler( VGA_PAGE_A0, 16, &vgaph.empty );
		vgapages.base=VGA_PAGE_B0;
		if (vga.herc.enable_bits & 0x2) {
			vgapages.mask=0xffff;
			MEM_SetPageHandler(VGA_PAGE_B0,16,&vgaph.map);
		} else {
			vgapages.mask=0x7fff;
			// With hercules in 32kB mode it leaves a memory hole on 0xb800
			// and has MDA-compatible address wrapping when graphics are disabled
			if (vga.herc.enable_bits & 0x1)
				MEM_SetPageHandler(VGA_PAGE_B0,8,&vgaph.map);
			else
				MEM_SetPageHandler(VGA_PAGE_B0,8,&vgaph.herc);
			MEM_SetPageHandler(VGA_PAGE_B8,8,&vgaph.empty);
		}
		goto range_done;
	case MCH_TANDY:
		/* Always map 0xa000 - 0xbfff, might overwrite 0xb800 */
		vgapages.base=VGA_PAGE_A0;
		vgapages.mask=0x1ffff;
		MEM_SetPageHandler(VGA_PAGE_A0, 32, &vgaph.map );
		if ( vga.tandy.extended_ram & 1 ) {
			//You seem to be able to also map different 64kb banks, but have to figure that out
			//This seems to work so far though
			vga.tandy.draw_base = vga.mem.linear;
			vga.tandy.mem_base = vga.mem.linear;
		} else {
			vga.tandy.draw_base = TANDY_VIDBASE( vga.tandy.draw_bank * 16 * 1024);
			vga.tandy.mem_base = TANDY_VIDBASE( vga.tandy.mem_bank * 16 * 1024);
			MEM_SetPageHandler( VGA_PAGE_B8, 8, &vgaph.tandy );
		}
		goto range_done;
//		MEM_SetPageHandler(vga.tandy.mem_bank<<2,vga.tandy.is_32k_mode ? 0x08 : 0x04,range_handler);
	case EGAVGA_ARCH_CASE:
		break;
	default:
		LOG_MSG("Illegal machine type %d", machine );
		return;
	}

	/* This should be vga only */
	switch (vga.mode) {
	case M_ERROR:
	default:
		return;
	case M_LIN4:
		newHandler = &vgaph.lin4;
		break;	
	case M_LIN15:
	case M_LIN16:
	case M_LIN24:
	case M_LIN32:
#ifdef VGA_LFB_MAPPED
		newHandler = &vgaph.map;
#else
		newHandler = &vgaph.changes;
#endif
		break;
	case M_LIN8:
	case M_VGA:
		if (vga.config.chained) {
			if(vga.config.compatible_chain4)
				newHandler = &vgaph.cvga;
			else 
#ifdef VGA_LFB_MAPPED
				newHandler = &vgaph.map;
#else
				newHandler = &vgaph.changes;
#endif
		} else {
			newHandler = &vgaph.uvga;
		}
		break;
	case M_EGA:
		if (vga.config.chained) 
			newHandler = &vgaph.cega;
		else
			newHandler = &vgaph.uega;
		break;	
	case M_TEXT:
		/* Check if we're not in odd/even mode */
		if (vga.gfx.miscellaneous & 0x2) newHandler = &vgaph.map;
		else newHandler = &vgaph.text;
		break;
	case M_CGA4:
	case M_CGA2:
		newHandler = &vgaph.map;
		break;
	}
	switch ((vga.gfx.miscellaneous >> 2) & 3) {
	case 0:
		vgapages.base = VGA_PAGE_A0;
		switch (svgaCard) {
		case SVGA_TsengET3K:
		case SVGA_TsengET4K:
			vgapages.mask = 0xffff;
			break;
		case SVGA_S3Trio:
		default:
			vgapages.mask = 0x1ffff;
			break;
		}
		MEM_SetPageHandler(VGA_PAGE_A0, 32, newHandler );
		break;
	case 1:
		vgapages.base = VGA_PAGE_A0;
		vgapages.mask = 0xffff;
		MEM_SetPageHandler( VGA_PAGE_A0, 16, newHandler );
		MEM_SetPageHandler( VGA_PAGE_B0, 16, &vgaph.empty );
		break;
	case 2:
		vgapages.base = VGA_PAGE_B0;
		vgapages.mask = 0x7fff;
		MEM_SetPageHandler( VGA_PAGE_B0, 8, newHandler );
		MEM_SetPageHandler( VGA_PAGE_A0, 16, &vgaph.empty );
		MEM_SetPageHandler( VGA_PAGE_B8, 8, &vgaph.empty );
		break;
	case 3:
		vgapages.base = VGA_PAGE_B8;
		vgapages.mask = 0x7fff;
		MEM_SetPageHandler( VGA_PAGE_B8, 8, newHandler );
		MEM_SetPageHandler( VGA_PAGE_A0, 16, &vgaph.empty );
		MEM_SetPageHandler( VGA_PAGE_B0, 8, &vgaph.empty );
		break;
	}
	if(svgaCard == SVGA_S3Trio && (vga.s3.ext_mem_ctrl & 0x10))
		MEM_SetPageHandler(VGA_PAGE_A0, 16, &vgaph.mmio);
range_done:
	PAGING_ClearTLB();
}

void VGA_StartUpdateLFB(void) {
	vga.lfb.page = vga.s3.la_window << 4;
	vga.lfb.addr = vga.s3.la_window << 16;
#ifdef VGA_LFB_MAPPED
	vga.lfb.handler = &vgaph.lfb;
#else
	vga.lfb.handler = &vgaph.lfbchanges;
#endif
	MEM_SetLFB(vga.lfb.page, vga.vmemsize / 4096, vga.lfb.handler, &vgaph.mmio);
}

static void VGA_Memory_ShutDown(Section * /*sec*/) {
#ifdef VGA_KEEP_CHANGES
	delete[] vga.changes.map;
#endif
}

void VGA_SetupMemory(Section* sec) {
	vga.svga.bank_read = vga.svga.bank_write = 0;
	vga.svga.bank_read_full = vga.svga.bank_write_full = 0;

	// ensure memory is aligned to vga_memalign bytes
	assert(reinterpret_cast<uintptr_t>(vga.mem.linear) % vga_memalign == 0);
	assert(reinterpret_cast<uintptr_t>(vga.fastmem) % vga_memalign == 0);

	uint32_t vga_allocsize=vga.vmemsize;
	// Keep lower limit at 512k
	if (vga_allocsize<512*1024) vga_allocsize=512*1024;
	// We reserve extra 2K for one scan line
	vga_allocsize+=2048;

	memset(vga.mem.linear,0,vga_allocsize);

	// In most cases these values stay the same. Assumptions: vmemwrap is power of 2,
	// vmemwrap <= vmemsize, fastmem implicitly has mem wrap twice as big
	vga.vmemwrap = vga.vmemsize;

#ifdef VGA_KEEP_CHANGES
	memset( &vga.changes, 0, sizeof( vga.changes ));
	int changesMapSize = (vga.vmemsize >> VGA_CHANGE_SHIFT) + 32;
	vga.changes.map = new uint8_t[changesMapSize];
	memset(vga.changes.map, 0, changesMapSize);
#endif
	vga.svga.bank_read = vga.svga.bank_write = 0;
	vga.svga.bank_read_full = vga.svga.bank_write_full = 0;
	vga.svga.bank_size = 0x10000; /* most common bank size is 64K */

	sec->AddDestroyFunction(&VGA_Memory_ShutDown);

	if (machine==MCH_PCJR) {
		/* PCJr does not have dedicated graphics memory but uses
		   conventional memory below 128k */
		//TODO map?	
	} 
}
