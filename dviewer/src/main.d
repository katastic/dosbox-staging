bool isUnchained = true;
int RES_WIDTH = 320/4;
int RES_HEIGHT = 200;
float SCALE=2;
int canvasW = 1366;	// canvas size
int canvasH = 2000;	// ''
uint CONFIG_frameToStartDrawing = 0; //if higher than 0, we'll handle pops but not draw anything. So we can setup palette, and also skip to specific sections
uint CONFIG_frameToEnd = 0; //if higher than -1, we'll restart at X. [NYI]

uint drawMask = 0xFFFFFFFF;
bool isDrawMaskOn = false;

frame[] frames;
bool firstRun=true;
int currentExpectedFrame = -1024;
File file;
frame currentFrame;
int totalOps=0;
int totalPops=0;
int opsRun = 0;
int OpsPerDraw = 512;
bool flipPerFrame = false;
bool doReorder = false;
bool isPaused = false;
bool doSaveFrames = false;
float parsingTime = -1;
ulong currentFrameBeingDrawn = 0;
StopWatch sw3;

struct pixel
	{
	int x, y;
	ubyte c;
	}

/+
	- redraw frame -> screen, using current palette (shader?) Or do we already do that? So we get palette fades and cycling


	---> We might need to swap to a binary output format from DOSBOX if simply because the CSVs are so huge that D's built-in CSV handler chokes on them significantly enough to impact the testing cycle.
		- sqlite:
			https://wiki.dlang.org/Database_Libraries	
		- custom: our packet structure is SUPER SIMPLE. In fact, identical for all ATM so we only really need a one-size-fits-all [array-length strings] + ints

	--> also, CSVs are freakin' HUGE. The flaw, however, is we can no longer [[grep]] through files.


	- start/ending frame indicators still won't help the CSV parse faster.


	[ ] GUI indicators for draw type, or pop
		
		WRITING		[
			[x] 1 byte		[ ] pop
			[ ] 2 bytes		[ ] sop
			[ ] 4 bytes		[ ] text

	[+] TODO: Separate parseData from playData so we can loop
	
	[ ] OVERLAY. highlight a COLOR for each DRAW TYPE. (hello13b, vs hello14w, etc)
	[ ] or, allow highlighting only a specific draw type [would have to decouple canvas, canvasCombined, into highlightedCanvas+canvas -> canvasCombined]


	----> looks like in frame mode we're somehow still overwriting [canvasCombined] with zeros? 


	- not directly storing SOPS system operations like vsync. it's implicit in the frame boundary. assuming we actually have the right frame boundary trigger.

	[x] - GET STARTING PALETTE SOMEWHERE  [probably default windows one and not IBM BIOS but whatever]

	- [GUI] let us PAUSE THE DRAWING [also allow keyboard input during], as well as BACKUP A FRAME and move FORWARD a frame, and draw JUST [canvas] or [canvasCombined]
		- let us change the [op] batch size, or view frame mode.
		- dump screenshots of specific frames of canvas/canvascombined

	how do we want to handle showing changes? if we dump to a canvas, changes are gone.
		We could draw twice. 
			Draw to [canvas]	(not cleared every frame)
			Draw same routines to [canvas_highlight] 	(cleared every op, or # of ops)
			then combine the second onto the first. with some way to blend them so it's just brighter than the original.

			- but how do we handle setTarget and LOCKING bullshit?

			we could just keep [newCanvas] as well as [lastCanvas]
				lastCanvas is the accumulator
				newCanvas has new data drawn NORMAL but when drawn to SCREEN it has additional blending applied
				then, combine [newCanvas] into [lastCanvas], clear [newCanvas] and start over.

+/
// GLOBAL CONSTANTS
// =============================================================================
immutable bool DEBUG_NO_BACKGROUND = false; /// No graphical background so we draw a solid clear color. Does this do anything anymore?

// =============================================================================

import std.array;
import std.csv;
import std.typecons;
import std.stdio;
import std.conv;
import std.string;
import std.format;
import std.random;
import std.algorithm;
import std.traits; // EnumMembers
import std.datetime;
import std.datetime.stopwatch : benchmark, StopWatch, AutoStart;

pragma(lib, "dallegro5dmd"); // HOLY GOD, make sure this is the right one. (ldc vs DMD) we should fix this for new project templates later to autodetect.

version(ALLEGRO_NO_PRAGMA_LIB){}else{
	pragma(lib, "allegro");	// these ARE in fact used.
	pragma(lib, "allegro_primitives");
	pragma(lib, "allegro_image");
	pragma(lib, "allegro_font");
	pragma(lib, "allegro_ttf");
	pragma(lib, "allegro_color");
	pragma(lib, "allegro_audio");
	pragma(lib, "allegro_acodec");
	}

import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;
import allegro5.allegro_color;
import allegro5.allegro_audio;

import helper;
import g;

display_t display;
bitmap* paletteAtlas;
bitmap* canvas;
bitmap* canvasCombined;
bitmap* canvasCombinedReordered;

//=============================================================================

bool initialize()
	{	
	al_set_config_value(al_get_system_config(), "trace", "level", "info"); // enable logging. see https://github.com/liballeg/allegro5/issues/1339
	// "debug"
	if (!al_init())
		{
		auto ver 		= al_get_allegro_version();
		auto major 		= ver >> 24;
		auto minor 		= (ver >> 16) & 255;
		auto revision 	= (ver >> 8) & 255;
		auto release 	= ver & 255;

		writefln("The system Allegro version (%s.%s.%s.%s) does not match the version of this binding (%s.%s.%s.%s)",
			major, minor, revision, release,
			ALLEGRO_VERSION, ALLEGRO_SUB_VERSION, ALLEGRO_WIP_VERSION, ALLEGRO_RELEASE_NUMBER);

		assert(0, "The system Allegro version does not match the version of this binding!");
		}else{
				writefln("The Allegro version (%s.%s.%s.%s)",
			ALLEGRO_VERSION, ALLEGRO_SUB_VERSION, ALLEGRO_WIP_VERSION, ALLEGRO_RELEASE_NUMBER);
		}
	
static if (false) // MULTISAMPLING. Not sure if helpful.
	{
	with (ALLEGRO_DISPLAY_OPTIONS)
		{
		al_set_new_display_option(ALLEGRO_SAMPLE_BUFFERS, 1, ALLEGRO_REQUIRE);
		al_set_new_display_option(ALLEGRO_SAMPLES, 8, ALLEGRO_REQUIRE);
		}
	}

	al_display 	= al_create_display(g.SCREEN_W, g.SCREEN_H);
	queue		= al_create_event_queue();

	if (!al_install_keyboard())      assert(0, "al_install_keyboard failed!");
	if (!al_install_mouse())         assert(0, "al_install_mouse failed!");
	if (!al_init_image_addon())      assert(0, "al_init_image_addon failed!");
	if (!al_init_font_addon())       assert(0, "al_init_font_addon failed!");
	if (!al_init_ttf_addon())        assert(0, "al_init_ttf_addon failed!");
	if (!al_init_primitives_addon()) assert(0, "al_init_primitives_addon failed!");
	
	al_register_event_source(queue, al_get_display_event_source(al_display));
	al_register_event_source(queue, al_get_keyboard_event_source());
	al_register_event_source(queue, al_get_mouse_event_source());
	
	with(ALLEGRO_BLEND_MODE)
		{
		al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ONE, ALLEGRO_INVERSE_ALPHA);
//		al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ALPHA, ALLEGRO_INVERSE_ALPHA);
		}
				
	// load animations/etc
	// --------------------------------------------------------
	g.loadResources();
	
	// FPS Handling
	// --------------------------------------------------------
	fps_timer 		= al_create_timer(1.0f);
	screencap_timer = al_create_timer(7.5f);
	al_register_event_source(queue, al_get_timer_event_source(fps_timer));
	al_register_event_source(queue, al_get_timer_event_source(screencap_timer));
	al_start_timer(fps_timer);
	al_start_timer(screencap_timer);
	
	return 0;
	}
	
struct display_t
	{
	void startFrame()	
		{
		g.stats.reset();
//		resetClipping(); //why would we need this? One possible is below! To clear to color the whole screen!
//		al_clear_to_color(ALLEGRO_COLOR(1,0,0,1)); //only needed if we aren't drawing a background
		}
		
	void endFrame()
		{	
		al_flip_display();
		}

	void drawFrame()
		{
		startFrame();
		//------------------
		draw2();
		//------------------
		endFrame();
		}

	void resetClipping()
		{
//		al_set_clipping_rectangle(0, 0, g.SCREEN_W-1, g.SCREEN_H-1);
		}
		
	void draw2()
		{		
		static if(DEBUG_NO_BACKGROUND)
			al_clear_to_color(ALLEGRO_COLOR(0, 0, 0, 1));
		
		// Draw FPS and other text
		//display.resetClipping();
		
		float last_position_plus_one = textHelper(false); // we use the auto-intent of one initial frame to find the total text length for the box
		textHelper(true);  //reset

		float ifNotZeroPercent(T)(T stat)
			{
			if(stat[0] + stat[1] == 0)
				return 100;
			else
				return cast(float)stat[1] / (cast(float)stat[0] + cast(float)stat[1]) * 100.0;
			}
		}
	}

void logic()
	{
	}

void mouseLeft()
	{
	}
	
void mouseRight()
	{
	}

void execute()
	{
	bool once=false;
	bool isSpacePressed=false;
	bool isEPressed=false;
	bool isQPressed=false;
	if(!once){executeOnce(); once = true;}
	ALLEGRO_EVENT event;
		
	bool isKey(ALLEGRO_KEY key)
		{
		// captures: event.keyboard.keycode
		return (event.keyboard.keycode == key);
		}

	void isKeySet(ALLEGRO_KEY key, ref bool setKey)
		{
		// captures: event.keyboard.keycode
		if(event.keyboard.keycode == key)
			{
			setKey = true;
			}
		}
	void isKeyRel(ALLEGRO_KEY key, ref bool setKey)
		{
		// captures: event.keyboard.keycode
		if(event.keyboard.keycode == key)
			{
			setKey = false;
			}
		}
		
	bool exit = false;
	while(!exit)
		{
		drawData();
		if(!isPaused)currentFrameBeingDrawn++;
		if(isSpacePressed)
			{
			isPaused = !isPaused;
			isSpacePressed = false;
			}
		if(isEPressed)
			{
			currentFrameBeingDrawn++;
			// overrunning it is handled in the draw function.
			isEPressed = false;
			}
		if(isQPressed)
			{
			currentFrameBeingDrawn--;
			if(currentFrameBeingDrawn < 0)currentFrameBeingDrawn = frames.length - 1;
			isQPressed = false;
			}

		while(al_get_next_event(queue, &event))
			{
			switch(event.type)
				{
				case ALLEGRO_EVENT_DISPLAY_CLOSE:
					{
					exit = true;
					break;
					}
				case ALLEGRO_EVENT_KEY_DOWN:
					{						
					isKeySet(KEY_ESCAPE, exit);
					isKeySet(KEY_SPACE, isSpacePressed);
					isKeySet(KEY_E, isEPressed);
					isKeySet(KEY_Q, isQPressed);
					if(isKey(KEY_1))currentFrameBeingDrawn = cast(ulong)(frames.length * .10);
					if(isKey(KEY_2))currentFrameBeingDrawn = cast(ulong)(frames.length * .20);
					if(isKey(KEY_3))currentFrameBeingDrawn = cast(ulong)(frames.length * .30);
					if(isKey(KEY_4))currentFrameBeingDrawn = cast(ulong)(frames.length * .40);
					if(isKey(KEY_5))currentFrameBeingDrawn = cast(ulong)(frames.length * .50);
					if(isKey(KEY_6))currentFrameBeingDrawn = cast(ulong)(frames.length * .60);
					if(isKey(KEY_7))currentFrameBeingDrawn = cast(ulong)(frames.length * .70);
					if(isKey(KEY_8))currentFrameBeingDrawn = cast(ulong)(frames.length * .80);
					if(isKey(KEY_9))currentFrameBeingDrawn = cast(ulong)(frames.length * .90);
					if(isKey(KEY_0))currentFrameBeingDrawn = 0;
					if(isKey(KEY_R))RES_WIDTH = 80;
					if(isKey(KEY_T))RES_WIDTH = 160;					
					if(isKey(KEY_Y))RES_WIDTH = 256;					
					if(isKey(KEY_U))RES_WIDTH = 320;										
					if(isKey(KEY_I))RES_WIDTH = 640;
					
					if(isKey(KEY_F1)){drawMask = 0xFF00_0000; isDrawMaskOn = true;}
					if(isKey(KEY_F2)){drawMask = 0x00FF_0000; isDrawMaskOn = true;}
					if(isKey(KEY_F3)){drawMask = 0x0000_FF00; isDrawMaskOn = true;}
					if(isKey(KEY_F4)){drawMask = 0x0000_00FF; isDrawMaskOn = true;}
					if(isKey(KEY_F5)){drawMask = 0xFFFF_FFFF; isDrawMaskOn = true;}
					if(isKey(KEY_F6)){						  isDrawMaskOn = false;}

					if(isKey(ALLEGRO_KEY_OPENBRACE))RES_WIDTH--;					
					if(isKey(ALLEGRO_KEY_CLOSEBRACE))RES_WIDTH++;					
					
					keyPressed[event.keyboard.keycode] = true;
					break;
					}
					
				case ALLEGRO_EVENT_KEY_UP:				
					{
					keyPressed[event.keyboard.keycode] = false;
					break;
					}

				case ALLEGRO_EVENT_MOUSE_AXES:
					{
					g.mouse_x = event.mouse.x;
					g.mouse_y = event.mouse.y;
					g.mouse_in_window = true;
					break;
					}

				case ALLEGRO_EVENT_MOUSE_ENTER_DISPLAY:
					{
					writeln("mouse enters window");
					g.mouse_in_window = true;
					break;
					}
				
				case ALLEGRO_EVENT_MOUSE_LEAVE_DISPLAY:
					{
					writeln("mouse left window");
					g.mouse_in_window = false;
					break;
					}

				case ALLEGRO_EVENT_MOUSE_BUTTON_DOWN:
					{
					if(!g.mouse_in_window)break;
					
					if(event.mouse.button == 1)mouseLeft();
					if(event.mouse.button == 2)mouseRight();
					break;
					}
				
				case ALLEGRO_EVENT_MOUSE_BUTTON_UP:
					{
					g.mouse_lmb = false;
					break;
					}
				
				case ALLEGRO_EVENT_TIMER:
					{
					if(event.timer.source == screencap_timer)
						{
//						al_stop_timer(screencap_timer); // Do this FIRST so inner code cannot take so long as to re-trigger timers.
	//					writeln("saving screenshot [screen.png]");
		//				al_save_screen("screen.png");	
//	auto sw = StopWatch(AutoStart.yes);
//						al_save_bitmap("screen.png", al_get_backbuffer(al_display));
//				sw.stop();
//	int secs, msecs;
//	sw.peek.split!("seconds", "msecs")(secs, msecs);
//	writefln("Saving screenshot took %d.%ds", secs, msecs);
			}						
					if(event.timer.source == fps_timer) //ONCE per second
						{
						g.stats.fps = g.stats.frames_passed;
						g.stats.frames_passed = 0;
						}
					break;
					}
				default:
				}
			}

		logic();
		display.drawFrame();
		g.stats.frames_passed++;
//		Fiber.yield();  // THIS SEGFAULTS. I don't think this does what I thought.
//		pthread_yield(); //doesn't seem to change anything useful here. Are we already VSYNC limited to 60 FPS?
		}
	}

void shutdown() 
	{
	writeParsingTime();		
	}
	
void setupFloatingPoint()
	{
	import std.compiler : vendor, Vendor;
//	static if(vendor == Vendor.digitalMars)
		{
		import std.math.hardware : FloatingPointControl;
		FloatingPointControl fpctrl;
		fpctrl.enableExceptions(FloatingPointControl.severeExceptions);
		}
	// enables hardware trap exceptions on uninitialized floats (NaN), (I would imagine) division by zero, etc.
	// see 
	// 		https://dlang.org/library/std/math/hardware/floating_point_control.html
	// we could disable this on [release] mode if necessary for performance
	
	// LDC2 reports
	//   module hardware is in file 'std/math/hardware.d' which cannot be read

	}

void drawPalette(float x, float y, float scale)
	{	
	bitmap* restore = al_get_target_bitmap();
	
	al_set_target_bitmap(paletteAtlas);
	al_lock_bitmap(paletteAtlas, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
	for(ubyte i = 0; i < 16; i++)
		for(ubyte j = 0; j < 16; j++)
			{
			ubyte idx = cast(ubyte)(i + j*16);
			color c = al_map_rgb(CLT[idx].r, CLT[idx].g, CLT[idx].b);
			al_put_pixel(i, j, c);
			}	
	al_unlock_bitmap(paletteAtlas);	
	al_set_target_bitmap(restore);
	
	al_draw_tinted_scaled_bitmap(paletteAtlas, ALLEGRO_COLOR(1,1,1,1), 
		0, 0, paletteAtlas.w, paletteAtlas.h, 
		x, y, paletteAtlas.w*scale, paletteAtlas.h*scale, 0);	
	}

/*
	how do we handle anything "special" that might happen during a draw, that isn't a pixel and 
	isn't a VSYNC frame boundary?

		- what if data is drawn across two VSYNCS? (half rate)
		- what if there is no VSYNC?
		- what if something [PAN TRACE] or something happens in the middle of a vsync/draw op
		
	A separate set of special ops, [sops]? Or do we put it into the [op] struct?
	
	--> PALETTE UPDATES????
*/

struct sop /// system operation
	{
	bool isDisplayStartLatch=false;
	bool isPanningLatch=false;
	bool isVerticalTimer=false;
	}

struct triplet
	{
	ubyte r;
	ubyte g;
	ubyte b;
	}

triplet[256] CLT; /// colorLookupTable; 

struct pop /// palette (update) operation
	{
	
	this(ubyte _r, ubyte _g, ubyte _b)	
		{
		r = _r; g = _g; b = _b;
		}
		
	ubyte index;
	ubyte r, g, b;	
	}
	/+
		how are we EMULATING the color lookup table?
		
		- SIMPLEST METHOD so far, would be to just hit all pops for a frame then draw.
			- This covers the most COMMON case too... we just need a PALETTE LOADED and we don't want to worry about PLANNING DUMPS at the EXACT MOMENT we need them. This way is automatic and changes if palettes change (menu palette, vs game palette. Diablo 1's multiple level palettes. etc. Any game with streaming palettes.)
		- what about color cycling? (We could do a brute force "if matches RGB, change ALL of those matches", which will accidentally catch two pixels that have same RGBs but different INDEXes (two blacks in a palette). Rare (only when color cycling those specific colors) but possible. 
		- what about palette changes BETWEEN frames? (very rare on PC, AFAIK. Unlike Genesis which had like 61 total colors. 256 is huge for a SINGLE frame in the 90s.)
	
		- ALSO
	+/

struct op
	{
	int address;
	int bytes; //1, 2, or 4
	int[4] data; // the pixel data. note: given [bytes] rest of array is not used (=0)
	uint mask;
//	bool isSpecial; // false = pixel write. true = VTRACE, PAN, WINDOW, whatever?
	}

class frame 
	{
	op[] ops;
	pop[] pops;
	long frameNumber = -100; // just in case -1 or 0 get used for special data dumping flags 
	long maxAddress = -1;
	long minAddress = 10_000_000;
	int width;
	int height;
	
	void scanMinMax()   /// for max address, we ADD 1 (for word writes) and ADD 2 (for dword writes) since that's the last byte they touch?
		{
		foreach(op; ops)
			{
			if(op.address < minAddress)minAddress = op.address;
			if(op.address+(op.bytes-1) > maxAddress)maxAddress = op.address+(op.bytes-1);
			}
		}
	}

void parseData()
	{
	al_set_target_backbuffer(al_display);
	al_draw_filled_rectangle(200, 200, 300, 300, blue);
	drawPalette(1200, 0, 8);
	al_flip_display();
		
	// for each frame, track the min and max, address touched.
	writeln("PARSING CSV--------------------------------");

		foreach (record; file.byLine.joiner("\n").csvReader!(Tuple!(
				int, string, int, int, int,
				string, string, int, int, int, 
				int, int, int, uint)))
			{
				//writeln(record);
	//			writefln("%d,%s,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d",
		//			record[0], record[1], record[2], record[3], record[4], record[5],
			//		record[6], record[7], record[8], record[9], record[10], record[11],
				//	record[12]);
			
				if(currentExpectedFrame != record[0]) /// if we encounter a new frame
					{
					if(!firstRun)
						{
						frames ~= currentFrame; // throw last one on the pile
						}else{
						firstRun = false;
						}				

					currentExpectedFrame = record[0]; // new frame number
					currentFrame = new frame; // make struct
					currentFrame.frameNumber = currentExpectedFrame; // setup struct
					}
				
				bool isPrintable(T)(T val)
					{
					if(cast(char)val >= 32 && cast(char)val < 127)
						{
						return true;
						}else{
						return false;
						}	
					}
				
				switch(record[1])
					{
					case "VGA_VerticalTimer":
					case "VGA_DisplayStartLatch":
					case "VGA_PanningLatch":
					case "hello30b":	// EGA likely --> HANDLED BY 40A/B?
					case "hello31w":	// EGA ''
				
					case "hello14w":
									
	//					ubyte bytes = cast(ubyte)record[8];
		//				if(bytes == 1 && isPrintable(record[9]))writef("%c ", cast(char)record[9]);
			//			if(bytes == 2 && isPrintable(record[9]) && isPrintable(record[10]))writef("%c, %c ", cast(char)record[9], cast(char)record[10]);
				//		goto case; //dump text, but also draw just in case for now.
					
									
					case "hello40A":	// half packet 4 bytes	[EGA, 1 byte affects 2 pixels? 2 bytes = 4 pixels? But we're affecting 4x the bit planes?]
					case "hello40B":	// other half of packet 4 bytes [EGA writeHandler]

					case "hello55A":	// VGA writeHandler
					case "hello10b":
					case "hello11w":
					case "hello12d":
					case "hello13b":
					case "hello15d":
					// 	case "hello32d":	// EGA ''
						op o;
						o.address = record[7]; 
						o.bytes = record[8];
						o.mask = record[13];
						
						currentFrame.width = record[3]; // NOTE frame settings.
						currentFrame.height = record[4];
						if(o.bytes == 1) {o.data[0] = record[9];}
						if(o.bytes == 2) {o.data[0] = record[9]; o.data[1] = record[10];}
						if(o.bytes == 4) {o.data[0] = record[9]; o.data[1] = record[10]; o.data[2] = record[11]; o.data[3] = record[12];}
						currentFrame.ops ~= o;
						
						totalOps++;					
						//writeln("o.address: ", o.address, " for: ", o.data);
					break;
	/*
					case "hello16b":	// NOTE: 16b we're tossing a (text) mode byte on the end. (mode#=set color, set glyph, set etc) not being 
						if(record[6] != "EGA")break;	
						op o;
						o.address = record[7]; 
						o.bytes = 2;//record[8]; 16 colors = 4-bit nybbles
						currentFrame.width = record[3]; // NOTE frame settings.
						currentFrame.height = record[4];
						//if(o.bytes == 1) {o.data[0] = record[9] & 0b0000_0011;}
						//if(o.bytes == 2) {o.data[0] = record[9]; o.data[1] = record[10];}
						//if(o.bytes == 4) {o.data[0] = record[9]; o.data[1] = record[10]; o.data[2] = record[11]; o.data[3] = record[12];}
						o.data[0] = (record[9] & 0b1111_0000) << 2;
						o.data[1] =  record[9] & 0b0000_0011;
						
						
						writeln(record[9], " = ", o.data);
						currentFrame.ops ~= o;
						totalOps++;					
					break;*/

					case "palette":
						pop p;
						p.index = cast(ubyte)record[9];
						p.r = cast(ubyte)record[10];
						p.g = cast(ubyte)record[11];
						p.b = cast(ubyte)record[12];
						currentFrame.pops ~= p;
						totalPops++;
					break;
					default:
						writeln("WARNING: UNHANDLED PACKET TYPE ", record[1]);
					break;
					}								
			}
		frames ~= currentFrame; // last one onto the pile
		}

/// see here for JASC palettes https://lospec.com/palette-list/tag/8bit
void loadJASCPalette(string path)	// one site says JASC palettes have .BIN format. From Paintshop Pro.
	{
	import std.stdio;
	import std.file;
	import std.array : split;
	import std.conv;
	string line;
	auto fd = new File(path, "r");
	int i = 0;
	while ((line = fd.readln!string()) !is null) //https://forum.dlang.org/post/tbpmhkjjnqqxhsdzguls@forum.dlang.org
		{
		line = line.strip;
//		writeln("[",line,"]"); debug
		if(i == 0)assert(line == "JASC-PAL");
		//if(i == 1)assert(line == "0100"); version number? Not important
		if(i == 2)assert(line == "256");
		if(i > 2)
			{
			string[3] data = line.split(" ");
//			writeln(i-3, " = ", data); debug
			CLT[i-3].r = to!ubyte(data[0]);
			CLT[i-3].g = to!ubyte(data[1]);
			CLT[i-3].b = to!ubyte(data[2]);
			}
		i++;
		}
		
	// NOTE HACK: load default EGA palette in
	// https://en.wikipedia.org/wiki/Enhanced_Graphics_Adapter
	// 00 = 0
	// 55 = 85
	// AA = 170
	// FF = 255
	CLT[ 0] = triplet(  0,   0,   0); // black
	CLT[ 1] = triplet(  0,   0, 170); // blue
	CLT[ 2] = triplet(  0, 170,   0); // green
	CLT[ 3] = triplet(  0, 170, 170); // cyan
	CLT[ 4] = triplet(170,   0,   0); // red
	CLT[ 5] = triplet(170,   0, 170); // magenta
	CLT[ 6] = triplet(170,  85,   0); // brown 
	CLT[ 7] = triplet(170, 170, 170); // white / light gray
	CLT[ 8] = triplet( 85,  85,  85); // dark grey	
	CLT[ 9] = triplet( 85,  85, 255); // bright blue
	CLT[10] = triplet( 85, 255, 170); // bright green
	CLT[11] = triplet( 85, 255, 255); // bright cyan
	CLT[12] = triplet(255,  85, 170); // bright red
	CLT[13] = triplet(255,  85, 255); // bright magenta
	CLT[14] = triplet(255, 255,  85); // bright yellow
	CLT[15] = triplet(255, 255, 255); // bright white
	}
	
/// see here for JASC palettes https://lospec.com/palette-list/tag/8bit
void loadPalette(string path) // raw palette. which our website appears NOT to be giving us?! some wierd 2048 byte (2048/256 = 8 bytes per value?!)
	{
	import std.file;
	auto fd = new File(path, "r");
	for(int i = 0; i < 256; i++)
		{
		ubyte[3] data;		
		fd.rawRead(data);
		writeln(data);
		CLT[i].r = cast(ubyte)(data[0]);
		CLT[i].g = cast(ubyte)(data[1]);
		CLT[i].b = cast(ubyte)(data[2]);
		}
	}

void drawData()
	{	
	assert(canvas != null);
	if(currentFrameBeingDrawn > frames.length-1)currentFrameBeingDrawn = 0;
	
	int maxWidth=0, maxHeight=0;
	
	auto f = frames[currentFrameBeingDrawn];
		{		
		al_set_target_bitmap(canvas);
		// al_lock_bitmap(canvas, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
		static if (false) al_clear_to_color(ALLEGRO_COLOR(1,0,0,1)); // reset the canvas
		
		writefln("FRAME #%d (%d draw ops) (%d pops) -----------------------------------", f.frameNumber, f.ops.length, f.pops.length);

		// when drawing a frame we process any POPS first. (regardless of their timing within a frame, for simplicity)
		foreach(p; f.pops) // note CLT persists across frames.
			{
			CLT[p.index].r = p.r;
			CLT[p.index].g = p.g;
			CLT[p.index].b = p.b;
			} // NOTE: we may have to scale from 6 bits to 8 bits, like DOSBOX does, however, DOSBOX is already doing this somewhere and I might be logging those scaled values. see render.cpp:RENDER_SetPal() and vga_dac.cpp:76 calling scale_6_to_8(red)

		pixel getAddress(int address, int resWidth, int resHeight)
			{
			pixel p;
			p.x = (address % RES_WIDTH) * 4;
			p.y = address / RES_WIDTH;
			//p.x = address % RES_WIDTH;
			//p.y = address / RES_WIDTH;
			return p;
			}	

		foreach(o; f.ops)
			{
			if(f.frameNumber < CONFIG_frameToStartDrawing)continue;						
			pixel p1, p2, p3, p4;
			
			if(maxWidth  < p1.x)maxWidth  = p1.x; // NOTE, not testing p2, p3, p4, doesn't matter right now
			if(maxHeight < p1.y)maxHeight = p1.y;			
			
			if(o.bytes == 1)
				{
				writefln("%x %d", o.mask, o.mask);
				
				p1 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);					
				p1.c = cast(ubyte)o.data[0];
				writefln("[%d,%d] = %d [A:%d]", 
					p1.x, p1.y, p1.c, o.address);
					
				if(isUnchained)
					{
					if(o.mask == 0xFFFFFFFF) // WE GOTTA FIX THIS, we actually have a FOUR PIXEL run.
						{
						o.bytes = 4;	
						p2 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);	
						p2.x += 1;
						p2.c = cast(ubyte)o.data[1];
						
						p3 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);	
						p3.x += 2;
						p3.c = cast(ubyte)o.data[2];
						
						p4 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);	
						p4.x += 3;
						p4.c = cast(ubyte)o.data[3]; 
						
						// is this the right ordering? or backwards?
						}
					else if(o.mask == 0x000000FF)p1.x+=0;
					else if(o.mask == 0x0000FF00)p1.x+=1;
					else if(o.mask == 0x00FF0000)p1.x+=2;
					else if(o.mask == 0xFF000000)p1.x+=3;
					}
				}
				
			if(o.bytes == 2)
				{
//				if(maxWidth < x+1)maxWidth = x+1;				
				p1 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);	
				p1.c = cast(ubyte)o.data[0];
				p2 = getAddress(o.address+1, RES_WIDTH, RES_HEIGHT);	
				p2.c = cast(ubyte)o.data[1];
				writefln("[%d,%d] = %d [A:%d], [%d,%d] = %d [A:%d]", 
					p1.x, p1.y, p1.c, o.address, 
					p2.x, p2.y, p2.c, o.address);
				p2.x += 1;
				}

			if(o.bytes == 4)
				{				
				if(isDrawMaskOn && o.mask != drawMask)continue;
				writefln("%08x", o.mask);				
				//if(maxWidth < x+3)maxWidth = x+3;	
				p1 = getAddress(o.address  , RES_WIDTH, RES_HEIGHT);	
				p1.c = cast(ubyte)o.data[0];
				p2 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);					
				p2.c = cast(ubyte)o.data[1];
				p2.x += 1;
				p3 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);	
				p3.c = cast(ubyte)o.data[2];
				p3.x += 2;
				p4 = getAddress(o.address, RES_WIDTH, RES_HEIGHT);	
				p4.c = cast(ubyte)o.data[3];
				p4.x += 3;
				writefln("[%d,%d] = %d [A:%d], [%d,%d] = %d [A:%d], [%d,%d] = %d [A:%d], [%d,%d] = %d [A:%d]", 
					p1.x, p1.y, p1.c, o.address, 
					p2.x, p2.y, p2.c, o.address + 1,
					p3.x, p3.y, p3.c, o.address + 2,
					p4.x, p4.y, p4.c, o.address + 3,
					);
				}
			
			assert(o.address >= 0);
			assert(p1.x >= 0);
			assert(p1.y >= 0);
			assert(p2.x >= 0);
			assert(p2.y >= 0);
			if(doReorder)
				{
				int nx;
				
				//y += 200*(x/80);
				
				//nx = (nx*4)%RES_WIDTH - (3 - 1*nx%RES_WIDTH);				
				//x = nx;
					
					/*
				int nx = 0;
				if(			         x < 80*1)nx = x*4 - 80 + 0;
				else if(x >= 80   && x < 80*2)nx = x*4 - 80*2 + 1;
				else if(x >= 80*2 && x < 80*3)nx = x*4 - 80*3 + 2;
				else if(x >= 80*3 && x < 80*4)nx = x*4 - 80*4 + 3;
				x = nx;
				writeln(x);
				*/
				//writeln("x,y was ", x,",",y);
				/*
				const int s = 2;
																		
				if		 (	   		     x < 80){x = x*s; 			    y = y*s + 0;} 
				  else if(x >= 80   && x < 80*2){x = x*s + -80*s*1 + 1;	y = y*2 + 0;}
				  else if(x >= 80*2 && x < 80*3){x = x*s + -80*s*2 + 0;	y = y*2 + 1;}
				  else if(x >= 80*3 && x < 80*4){x = x*s + -80*s*3 + 1;	y = y*2 + 1;}*/
//				writeln("x,y  is ", x,",",y);
				//assert(x < 320);
				//assert(y < 200);
				//y *= 2;
				// ---> we might need to do a 2D re-ordering. 4 screens = 0,0; 0,1; 1,0; 1,1. pushed out across a square.
				
				// x = (x*20 + x/(320/20))%320;
				 // x = (x*80 + x)%320;		
				// x = (x%4)*80 + x/4; // nope. this splits 4 into 16
				// x = (x*80 + x/4)%320; now we've got 16.... but they're incrementing by 80...
				// 	x = (x*80 + x/(320/80))%320;				
				}
				
			if(o.bytes == 1) 
				{
				al_draw_pixel(p1.x + 0.5    , p1.y + 0.5, al_map_rgb(CLT[p1.c].r, CLT[p1.c].g, CLT[p1.c].b));
				}
			if(o.bytes == 2)
				{
				al_draw_pixel(p2.x + 0.5    , p2.y + 0.5, al_map_rgb(CLT[p1.c].r, CLT[p1.c].g, CLT[p1.c].b));
				al_draw_pixel(p1.x + 0.5 + 1, p1.y + 0.5, al_map_rgb(CLT[p2.c].r, CLT[p2.c].g, CLT[p2.c].b));	
				}
			if(o.bytes == 4)
				{
				al_draw_pixel(p4.x + 0.5    , p4.y + 0.5, al_map_rgb(CLT[p4.c].r, CLT[p4.c].g, CLT[p4.c].b));
				al_draw_pixel(p3.x + 0.5 + 1, p3.y + 0.5, al_map_rgb(CLT[p3.c].r, CLT[p3.c].g, CLT[p3.c].b));	
				al_draw_pixel(p2.x + 0.5 + 2, p2.y + 0.5, al_map_rgb(CLT[p2.c].r, CLT[p2.c].g, CLT[p2.c].b));
				al_draw_pixel(p1.x + 0.5 + 3, p1.y + 0.5, al_map_rgb(CLT[p1.c].r, CLT[p1.c].g, CLT[p1.c].b));				
				}
			
			// writeln("  write ", o.bytes, " bytes: ", c1, " ", c2, " ", c3, " ", c4, " at ", x, " ", y, " addr[", o.address, "]"); //debug
			opsRun++;
			if(opsRun >= OpsPerDraw && !flipPerFrame) // END OF OPS BATCH, TRIGGER A DRAW
				{
				// now draw BOTH layers to [screen] separately, with tinting for newest additions
				// ------------------------------------------------------------------------------------------------
				al_set_target_backbuffer(al_display);
					al_clear_to_color(ALLEGRO_COLOR(0,0,0,1));			
					
					al_draw_tinted_scaled_bitmap(canvasCombined, ALLEGRO_COLOR(1,1,1,1), 0, 0, canvasCombined.w, canvasCombined.h, 0, 0, canvasCombined.w*SCALE, canvasCombined.h*SCALE, 0);
					al_draw_tinted_scaled_bitmap(canvas, ALLEGRO_COLOR(1,.5,.5,1), 0, 0, canvas.w, canvas.h, 0, 0, canvas.w*SCALE, canvas.h*SCALE, 0);
					
					drawPalette(1200, 0, 8);
					al_draw_textf(font1, red, 800, 10+28*0, 0, "FRAME %d", f.frameNumber);
					al_draw_textf(font1, red, 800, 10+28*1, 0, "index %d", currentFrameBeingDrawn);
					al_draw_textf(font1, red, 800, 10+28*2, 0, "%dx%d", RES_WIDTH, RES_HEIGHT);
					al_draw_textf(font1, red, 800, 10+28*3, 0, "mask %08x", drawMask);
				al_flip_display();

				// ------------------------------------------------------------------------------------------------
				if(f.frameNumber > 900 && doSaveFrames)
					{
					al_save_bitmap(format("frames/c%d.png", f.frameNumber).toStringz(), canvas);
					al_save_bitmap(format("frames/cc%d.png", f.frameNumber).toStringz(), canvasCombined);
					}
					
				// now combine our old work into canvasCombined and then clear the other canvas
				// ------------------------------------------------------------------------------------------------
				al_set_target_bitmap(canvasCombined);
				al_draw_bitmap(canvas, 0, 0, 0); // into ^^^canvasCombined								
					
				// Start of next run, clear canvas:
				// ------------------------------------------------------------------------------------------------
				al_set_target_bitmap(canvas);
		//		al_lock_bitmap(canvas, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
				with(ALLEGRO_BLEND_MODE)
					{
					al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ZERO, ALLEGRO_ONE); // write alpha
					al_clear_to_color(ALLEGRO_COLOR(0,0,0,0)); // clear our working [canvas] to transparent
					al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ONE, ALLEGRO_INVERSE_ALPHA);
					}
				
				opsRun = 0;
				}// how many draws to 
			}
			
		if(flipPerFrame)
			{
			// In FRAME MODE, often the entire screen will be updated so we have to be careful not to tint everything...
//			al_unlock_bitmap(canvas); // finish drawing to [canvas]
			
			// now draw BOTH layers to [screen] separately, with tinting for newest additions
			al_set_target_backbuffer(al_display);
			al_clear_to_color(ALLEGRO_COLOR(0,0,0,1));			
		
			al_draw_tinted_scaled_bitmap(canvasCombined, ALLEGRO_COLOR(1,1,1,1), 0, 0, canvasCombined.w, canvasCombined.h, 0, 0, canvasCombined.w*SCALE, canvasCombined.h*SCALE, 0);
			al_draw_tinted_scaled_bitmap(canvas, ALLEGRO_COLOR(1,0,0,1), 0, 0, canvas.w, canvas.h, 0, 0, canvas.w*SCALE, canvas.h*SCALE, 0);
					
			drawPalette(600, 0, 4);
			al_draw_textf(font1, red, 800, 10*28*0, 0, "FRAME %d", f.frameNumber);			
			al_draw_textf(font1, red, 800, 10+28*1, 0, "index %d", currentFrameBeingDrawn);
			al_draw_textf(font1, red, 800, 10+28*2, 0, "%dx%d", RES_WIDTH, RES_HEIGHT);
			al_draw_textf(font1, red, 800, 10+28*3, 0, "mask %08x", drawMask);
			al_flip_display();
			
			// now combine our old work into canvasCombined and clear the other canvas
			al_set_target_bitmap(canvasCombined);
			al_draw_bitmap(canvas, 0, 0, 0); // into canvasCombined
			
			if(f.frameNumber > 900)
				{
				al_save_bitmap(format("c%d.png", f.frameNumber).toStringz(), canvas);
				al_save_bitmap(format("cc%d.png", f.frameNumber).toStringz(), canvasCombined);
				}
			// now clear canvas and go back to drawing
			al_set_target_bitmap(canvas);
			with(ALLEGRO_BLEND_MODE)
				{
				al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ZERO, ALLEGRO_ONE); // write alpha
				al_clear_to_color(ALLEGRO_COLOR(0,0,0,0)); // clear our working [canvas] to transparent
				al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ONE, ALLEGRO_INVERSE_ALPHA);
				}
			// now ready to start adding ops again
			
			}
		}
	writeln("MaxW/H ", maxWidth, ",", maxHeight);	
	}

void executeOnce()
	{
	loadJASCPalette("./data/windows-95-256-colours.pal");
		
	sw3 = StopWatch();
	sw3.start();
	file = File(inputPath, "r");

	if(doReorder)
		{
		writeln("Using [REORDERED] drawing");
		}else{
		writeln("Using [normal] drawing");
		}
	
	if(flipPerFrame)
		{
		writeln(" - flipPerFrame = ON");		
		}else{
		writeln(" - flipPerFrame = OFF");	
		}						
	
	canvas = al_create_bitmap(canvasW, canvasH);
	canvasCombined = al_create_bitmap(canvasW, canvasH);
	canvasCombinedReordered = al_create_bitmap(canvasW, canvasH);
	paletteAtlas = al_create_bitmap(16, 16); // 16 * 16 = 256

	parseData();
	assert(canvas != null);
	sw3.stop();
	writeParsingTime();
	}
	
void writeParsingTime()
	{
	writeln("total frames: ", frames.length);
	writeln("total ops: ", totalOps);
	writeln("total pops: ", totalPops);
	parsingTime = (sw3.peek.total!"msecs")/1000.0;
	writefln("[Parsing] Time elapsed %3.2f seconds [%3.2fs / frame] [%3.2f ops/sec]", parsingTime, parsingTime/frames.length, totalOps/parsingTime);
	}

//=============================================================================
string inputPath;
int main(string [] args)
	{
	setupFloatingPoint();
	writeln("args length = ", args.length);
	foreach(size_t i, string arg; args)
		{
		writeln("[",i, "] ", arg);
		}
		
	if(args.length >= 2)
		{
		writeln("args:", args);
		inputPath = args[1];
		
		if(args.length >= 3)
			{
			CONFIG_frameToStartDrawing = to!uint(args[2]);
			writeln("Starting rendering at frame [", CONFIG_frameToStartDrawing, "]");
			}
		
		}else{
		writeln("args:", args, " using default path");
		inputPath = "/home/novous/Desktop/git/dosbox-staging/build/output2.txt";
		}

	return al_run_allegro(
		{
		initialize();
		execute();
		shutdown();
		return 0;
		});

	return 0;
	}
