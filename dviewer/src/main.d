/+


	OVERLAY. highlight a COLOR for each DRAW TYPE. (hello13b, vs hello14w, etc)


	----> looks like in frame mode we're somehow still overwriting [canvasCombined] with zeros? 


	- not directly storing SOPS system operations like vsync. it's implicit in the frame boundary. assuming we actually have the right frame boundary trigger.

	- GET STARTING PALETTE SOMEWHERE 

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
		/*
		al_set_clipping_rectangle(
			g.viewports[0].x, 
			g.viewports[0].y, 
			g.viewports[0].x + g.viewports[0].w ,  //-1
			g.viewports[0].y + g.viewports[0].h); //-1
		*/
		static if(DEBUG_NO_BACKGROUND)
			al_clear_to_color(ALLEGRO_COLOR(0, 0, 0, 1));
		
		// Draw FPS and other text
		//display.resetClipping();
		
		float last_position_plus_one = textHelper(false); // we use the auto-intent of one initial frame to find the total text length for the box
		textHelper(true);  //reset

//		al_draw_filled_rounded_rectangle(16, 32, 64+650, last_position_plus_one+32, 8, 8, ALLEGRO_COLOR(.7, .7, .7, .7));
/*
		drawText2(20, "fps[%d] objrate[%d]", g.stats.fps, 
					(g.stats.number_of_drawn_particles[0] +
					g.stats.number_of_drawn_units[0] + 
					g.stats.number_of_drawn_particles[0] + 
					g.stats.number_of_drawn_bullets[0] + 
					g.stats.number_of_drawn_structures[0]) * g.stats.fps ); 
	*/	

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
		//g.SCREEN_W = to!int(args[1]);
		//g.SCREEN_H = to!int(args[2]);
		//writeln("New resolution is ", g.SCREEN_W, "x", g.SCREEN_H);
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

triplet[256] CLT; // colorLookupTable; 

struct pop /// palette (update) operation
	{
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

// ---> TODO: Separate parseData from playData so we can loop
frame[] frames;
bool firstRun=true;
int currentExpectedFrame = -1024;
int firstFrameToRender = 1000;
File file;
frame currentFrame;
int totalOps=0;
int totalPops=0;
int opsRun = 0;
int OpsPerDraw = 256;
bool flipPerFrame = false;
bool doReorder=true;

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
			int, int, int, int, int)))
		{
			
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
			
			if(record[1] == "hello11w")
				{
				op o;
				o.address = record[7]; 
				o.bytes = record[8];
				currentFrame.width = record[3]; // NOTE frame settings
				currentFrame.height = record[4];
				if(o.bytes == 1) {o.data[0] = record[9];}
				if(o.bytes == 2) {o.data[0] = record[9]; o.data[1] = record[10];}
				if(o.bytes == 4) {o.data[0] = record[10]; o.data[1] = record[11]; o.data[2] = record[12]; o.data[3] = record[13];}
				currentFrame.ops ~= o;
				totalOps++;
				continue;
				}
						
			if(record[1] == "hello12d")
				{
				op o;
				o.address = record[7]; 
				o.bytes = record[8];
				currentFrame.width = record[3]; // NOTE frame settings
				currentFrame.height = record[4];
				if(o.bytes == 1) {o.data[0] = record[9];}
				if(o.bytes == 2) {o.data[0] = record[9]; o.data[1] = record[10];}
				if(o.bytes == 4) {o.data[0] = record[10]; o.data[1] = record[11]; o.data[2] = record[12]; o.data[3] = record[13];}
				currentFrame.ops ~= o;
				totalOps++;
				continue;
				}
						
			if(record[1] == "hello13b")
				{
				op o;
				o.address = record[7]; 
				o.bytes = record[8];
				currentFrame.width = record[3]; // NOTE frame settings
				currentFrame.height = record[4];
				if(o.bytes == 1) {o.data[0] = record[9];}
				if(o.bytes == 2) {o.data[0] = record[9]; o.data[1] = record[10];}
				if(o.bytes == 4) {o.data[0] = record[10]; o.data[1] = record[11]; o.data[2] = record[12]; o.data[3] = record[13];}
				currentFrame.ops ~= o;
				totalOps++;
				continue;
				}
				
			if(record[1] == "hello14w")
				{
				op o;
				o.address = record[7]; 
				o.bytes = record[8];
				currentFrame.width = record[3]; // NOTE frame settings
				currentFrame.height = record[4];
				if(o.bytes == 1) {o.data[0] = record[9];}
				if(o.bytes == 2) {o.data[0] = record[9]; o.data[1] = record[10];}
				if(o.bytes == 4) {o.data[0] = record[10]; o.data[1] = record[11]; o.data[2] = record[12]; o.data[3] = record[13];}
				currentFrame.ops ~= o;
				totalOps++;
				continue;
				}
				
			if(record[1] == "hello16b") 	// THIS IS VERY LIKELY TEXT.
				{
				op o;
				o.address = record[7]; 
				o.bytes = record[8];
				currentFrame.width = record[3]; // NOTE frame settings
				currentFrame.height = record[4];
				if(o.bytes == 1) {o.data[0] = record[9];}
				if(o.bytes == 2) {assert(false);} //never more than 1 byte
				if(o.bytes == 4) {assert(false);}
				
				if(false) currentFrame.ops ~= o; // ?Should we add these to our graphical packet op lists?
				if(false) printf("%c", o.data[0]); // dump to stdout. So far this is all junk data. Maybe setting regs or something???
				
				// --> what if this is the palette???
				
				// record[13] in this packet is a MODE specifier (almost always zero)
				continue;
				}
				
			if(record[1] == "palette")
				{
				pop p;
				p.index = cast(ubyte)record[9];
				p.r = cast(ubyte)record[10];
				p.g = cast(ubyte)record[11];
				p.b = cast(ubyte)record[12];
				currentFrame.pops ~= p;
				totalPops++;
				continue;
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
	writeln("DRAWING DATA--------------------------------");
	/*
	static ubyte i = 0;
	i++;
	al_set_target_bitmap(canvas);
	al_draw_filled_rectangle(20, 20, 100, 100, al_map_rgb(i,i,i));
	
	al_set_target_backbuffer(al_display);
	al_clear_to_color(ALLEGRO_COLOR(0,0,0,1));
	al_draw_bitmap(canvas, 0, 0, 0); // into ^^^canvasCombined
	al_flip_display();
	*/
	foreach(f; frames)
		{		
		al_set_target_bitmap(canvas);
		// al_lock_bitmap(canvas, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
		static if (false) al_clear_to_color(ALLEGRO_COLOR(1,0,0,1)); // reset the canvas
		float SCALE=3.0;
		writefln("FRAME #%d (%d draw ops) (%d pops) -----------------------------------", f.frameNumber, f.ops.length, f.pops.length);

		// when drawing a frame we process any POPS first. (regardless of their timing within a frame, for simplicity)
		foreach(p; f.pops) // note CLT persists across frames.
			{
			CLT[p.index].r = p.r;
			CLT[p.index].g = p.g;
			CLT[p.index].b = p.b;
			} // NOTE: we may have to scale from 6 bits to 8 bits, like DOSBOX does, however, DOSBOX is already doing this somewhere and I might be logging those scaled values. see render.cpp:RENDER_SetPal() and vga_dac.cpp:76 calling scale_6_to_8(red)

		foreach(o; f.ops)
			{
			if(f.frameNumber < firstFrameToRender)continue;
			ubyte c1 = cast(ubyte)o.data[0];
			ubyte c2, c3, c4;
			int x = o.address % 320;
			int y = o.address / 320;
			assert(o.address >= 0);
			assert(x >= 0);
			assert(y >= 0);
			if(doReorder)
				{
				// ---> we might need to do a 2D re-ordering. 4 screens = 0,0; 0,1; 1,0; 1,1. pushed out across a square.
				
				// x = (x*20 + x/(320/20))%320;
				// x = (x*80 + x)%320;		
				// x = (x%4)*80 + x/4; // nope. this splits 4 into 16
				// x = (x*80 + x/4)%320; now we've got 16.... but they're incrementing by 80...
				// 	x = (x*80 + x/(320/80))%320;
				/+
						write 155 0 at 5 5 addr[1620]
					  write 155 0 at 25 5 addr[1700]
					  write 152 0 at 45 5 addr[1780]
					  write 152 0 at 65 5 addr[1860]
					  write 152 0 at 5 6 addr[1940]
					  write 152 0 at 25 6 addr[2020]
					  write 153 0 at 45 6 addr[2100]
					  write 153 0 at 65 6 addr[2180]
					  write 153 0 at 5 7 addr[2260]
					  write 153 0 at 25 7 addr[2340]
					  write 155 0 at 45 7 addr[2420]
					  write 155 0 at 65 7 addr[2500]
					+/
				}
			al_draw_pixel(x  , y, al_map_rgb(CLT[c1].r, CLT[c1].g, CLT[c1].b));
			if(o.bytes >= 2)
				{
				c2 = cast(ubyte)o.data[1];
				al_draw_pixel(x+1, y, al_map_rgb(CLT[c2].r, CLT[c2].g, CLT[c2].b));	
				}
			if(o.bytes == 4) //4 bytes (there's no 3 byte messages)
				{
				c3 = cast(ubyte)o.data[2];
				c4 = cast(ubyte)o.data[3];
				al_draw_pixel(x+2, y, al_map_rgb(CLT[c2].r, CLT[c2].g, CLT[c2].b));					
				al_draw_pixel(x+3, y, al_map_rgb(CLT[c2].r, CLT[c2].g, CLT[c2].b));					
				}
			
			writeln("  write ", o.bytes, " bytes: ", c1, " ", c2, " ", c3, " ", c4, " at ", x, " ", y, " addr[", o.address, "]");
			opsRun++;
			if(opsRun >= OpsPerDraw && !flipPerFrame) // END OF OPS BATCH, TRIGGER A DRAW
				{
//				al_unlock_bitmap(canvas);
//				writeln("vsync");
				/*
				if (doReorder)
					{
					if(firstFrame)
						{
						firstFrame = false; // do nothing. skip it. we haven't blitted to canvasCombined yet and that's our snoop target.
						
						}else{
						al_set_target_bitmap(canvasCombinedReordered);
						al_lock_bitmap(canvasCombined, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_READONLY);
						al_lock_bitmap(canvasCombinedReordered, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
					
						with(ALLEGRO_BLEND_MODE)
							{
							al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ZERO, ALLEGRO_ONE); // write alpha
							for(int j = 0; j < 200; j++)
								for(int i = 0; i < 320; i++)
									{
									color c = al_get_pixel(canvasCombined, i, j);
									int X = i;// %4 + i%80 - i/80;
									int Y = j;
									al_put_pixel(X, Y, c);  //320/4 wide = 80
									writeln(i, " = ", X,",",Y, " set to:", c);
									}													
							al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ONE, ALLEGRO_INVERSE_ALPHA);
							}
						
						al_unlock_bitmap(canvasCombinedReordered);
						al_unlock_bitmap(canvasCombined);
						}
					}					
				*/
				// now draw BOTH layers to [screen] separately, with tinting for newest additions
				// ------------------------------------------------------------------------------------------------
				al_set_target_backbuffer(al_display);
					al_clear_to_color(ALLEGRO_COLOR(0,0,0,1));			
					
					al_draw_tinted_scaled_bitmap(canvasCombined, ALLEGRO_COLOR(1,1,1,1), 0, 0, canvasCombined.w, canvasCombined.h, 0, 0, canvasCombined.w*SCALE, canvasCombined.h*SCALE, 0);
					al_draw_tinted_scaled_bitmap(canvas, ALLEGRO_COLOR(1,.5,.5,1), 0, 0, canvas.w, canvas.h, 0, 0, canvas.w*SCALE, canvas.h*SCALE, 0);
					
					drawPalette(1200, 0, 8);
					al_draw_textf(font1, red, 600, 10, 0, "FRAME %d", f.frameNumber);
				al_flip_display();

				// ------------------------------------------------------------------------------------------------
				if(f.frameNumber > 900)
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
			al_draw_textf(font1, red, 600, 10, 0, "FRAME %d", f.frameNumber);			
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
	}

void executeOnce()
	{
	loadJASCPalette("./data/windows-95-256-colours.pal");
		
	auto sw3 = StopWatch();
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

	
	int w=320;
	int h=200;
	canvas = al_create_bitmap(w, h);
	canvasCombined = al_create_bitmap(w, h);
	canvasCombinedReordered = al_create_bitmap(w, h);
	paletteAtlas = al_create_bitmap(16, 16);

	parseData();
	assert(canvas != null);
	sw3.stop();
	writeln("total frames: ", frames.length);
	writeln("total ops: ", totalOps);
	writeln("total pops: ", totalPops);
	float secs = (sw3.peek.total!"msecs")/1000.0;
	writefln("[Parsing] Time elapsed %3.2f seconds [%3.2fs / frame] [%3.2f ops/sec]", secs, secs/frames.length, totalOps/secs);
	}

