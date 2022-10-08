/+

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

import std.stdio;
import std.conv;
import std.string;
import std.format;
import std.random;
import std.algorithm;
import std.traits; // EnumMembers
import std.datetime;
import std.datetime.stopwatch : benchmark, StopWatch, AutoStart;
//thread yielding?
//-------------------------------------------
//import core.thread; //for yield... maybe?
//extern (C) int pthread_yield(); //does this ... work? No errors yet I can't tell if it changes anything...
//------------------------------

pragma(lib, "dallegro5ldc");

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
bitmap* canvas;
bitmap* canvasCombined;

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

//=============================================================================
int main(string [] args)
	{
	setupFloatingPoint();
	writeln("args length = ", args.length);
	foreach(size_t i, string arg; args)
		{
		writeln("[",i, "] ", arg);
		}
		
	if(args.length > 2)
		{
		g.SCREEN_W = to!int(args[1]);
		g.SCREEN_H = to!int(args[2]);
		writeln("New resolution is ", g.SCREEN_W, "x", g.SCREEN_H);
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
	
	
	
	import std.algorithm;
import std.array;
import std.csv;
import std.stdio;
import std.typecons;

/*
	how do we handle anything "special" that might happen during a draw, that isn't a pixel and 
	isn't a VSYNC frame boundary?

		- what if data is drawn across two VSYNCS? (half rate)
		- what if there is no VSYNC?
		- what if something [PAN TRACE] or something happens in the middle of a vsync/draw op
		
	A separate set of special ops, [sops]? Or do we put it into the [op] struct?
*/

struct sop
	{
	bool isDisplayStartLatch=false;
	bool isPanningLatch=false;
	bool isVerticalTimer=false;
	}

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
File file;
frame currentFrame;

void parseData()
	{
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
				}
		}
	frames ~= currentFrame; // last one onto the pile
	}

void drawData()
	{
	assert(canvas != null);	

	int totalOps=0;
	int opsRun=0;
	bool flipPerFrame=false;
	writeln("DRAWING DATA--------------------------------");
	foreach(f; frames)
		{
		al_set_target_bitmap(canvas);
		//al_lock_bitmap(canvas, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
		al_clear_to_color(ALLEGRO_COLOR(0,0,0,1));

		writeln("FRAME ", f.frameNumber, " (", f.ops.length, " draw ops) ---------------------------------------------------------------");
		totalOps += f.ops.length;
		foreach(o; f.ops)
			{
			float c1 = o.data[0]/256.0;
			float c2 = o.data[1]/256.0;
			int x = o.address % 320;
			int y = o.address / 320;
			al_put_pixel(x  , y, ALLEGRO_COLOR(c1, c1, c1, 1));
			al_put_pixel(x+1, y, ALLEGRO_COLOR(c2, c2, c2, 1));
			
	//		writeln("write ", c1, " ", c2, " at ", x, " ", y, " addr[", o.address, "]");
			opsRun++;
			if(opsRun >= 256 && !flipPerFrame)
				{
				al_unlock_bitmap(canvas);
//				writeln("vsync");

				// now draw BOTH layers to [screen] separately, with tinting for newest additions
				al_set_target_backbuffer(al_display);
				al_clear_to_color(ALLEGRO_COLOR(0,0,0,1));
//				al_save_bitmap("canvasCombined.bmp", canvasCombined);
//				al_save_bitmap("canvas.bmp", canvas);
//				al_draw_bitmap(canvasCombined, 0, 0, 0); //update screen with canvas draws so far
//				al_draw_tinted_bitmap(canvas, ALLEGRO_COLOR(1,0,0,.5), 0, 0, 0); //newest canvas additions
				float SCALE=3.5;
				al_draw_tinted_scaled_bitmap(canvasCombined, ALLEGRO_COLOR(1,1,1,1), 0, 0, canvas.w, canvas.h, 0, 0, canvas.w*SCALE, canvas.h*SCALE, 0);
				al_draw_tinted_scaled_bitmap(canvas, ALLEGRO_COLOR(1,0,0,1), 0, 0, canvas.w, canvas.h, 0, 0, canvas.w*SCALE, canvas.h*SCALE, 0);

				al_draw_textf(font1, red, 600, 10, 0, "FRAME %d", f.frameNumber);
				al_flip_display();
	
				// now combine our old work into canvasCombined and then clear the other canvas
				al_set_target_bitmap(canvasCombined);
				al_draw_bitmap(canvas, 0, 0, 0); // into ^^^canvasCombined
					// WAIT, won't this overwrite canvasCombined?
				// Start of next run, clear canvas:
				al_set_target_bitmap(canvas);
		//		al_lock_bitmap(canvas, allegro5.color.ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ANY, ALLEGRO_LOCK_WRITEONLY);
				with(ALLEGRO_BLEND_MODE)
					{
					al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ZERO, ALLEGRO_ONE); // write alpha
					al_clear_to_color(ALLEGRO_COLOR(0,0,0,0)); // clear our working [canvas] to transparent
					al_set_blender(ALLEGRO_BLEND_OPERATIONS.ALLEGRO_ADD, ALLEGRO_ONE, ALLEGRO_INVERSE_ALPHA);
					}

			//	al_reset_target();
		//		al_clear_to_color(black);
//				al_flip_display(); //otherwise we're drawing to random page flips in memory and flickering
				opsRun = 0;
				}// how many draws to 
			}
		if(flipPerFrame)
			{
			// In FRAME MODE, often the entire screen will be updated so we have to be careful not to tint everything...
			al_unlock_bitmap(canvas); // finish drawing to [canvas]
			
			// now draw BOTH layers to [screen] separately, with tinting for newest additions
			al_set_target_backbuffer(al_display);
//			al_draw_bitmap(canvasCombined, 0, 0, 0); //update screen with canvas draws so far
float SCALE=4.0;
 al_draw_tinted_scaled_bitmap(canvasCombined, ALLEGRO_COLOR(1,0,0,1), 0, 0, canvas.w, canvas.h, 0, 0, canvas.w*SCALE, canvas.h*SCALE, 0);
//			al_draw_tinted_bitmap(canvas, ALLEGRO_COLOR(1,0,0,1), 0, 0, 0); //newest canvas additions
 al_draw_tinted_scaled_bitmap(canvas, ALLEGRO_COLOR(1,0,0,1), 0, 0, canvas.w, canvas.h, 0, 0, canvas.w*SCALE, canvas.h*SCALE, 0);
			al_flip_display();
			
			// now combine our old work into canvasCombined and clear the other canvas
			al_set_target_bitmap(canvasCombined);
			al_draw_bitmap(canvas, 0, 0, 0); // into canvasCombined
			al_set_target_bitmap(canvas);
			al_clear_to_color(black);
			// now ready to start adding ops again
			}
		}	
	writeln("total frames: ", frames.length);
	writeln("total ops: ", totalOps);
	}

void executeOnce()
	{
	file = File("/home/novous/Desktop/git/dosbox-staging/build/release/output2.txt", "r");
	parseData();
	canvas = al_create_bitmap(320, 200);
	canvasCombined = al_create_bitmap(320, 200);
	assert(canvas != null);
	}

