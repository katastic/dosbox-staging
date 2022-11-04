import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;
import allegro5.allegro_color;
import allegro5.allegro_audio;
import allegro5.allegro_acodec;

import std.stdio;
import std.file;
import std.math;
import std.conv;
import std.string;
import std.random;
import std.algorithm : remove;
import std.datetime;
import std.datetime.stopwatch : benchmark, StopWatch, AutoStart;

import helper;

int SCREEN_W = 1360; //not immutable because its a argc config variable
int SCREEN_H = 2000;
bool useLighting = true;
bool useGlowingBlood = true; // TODO FIX. fun bug: don't apply "light" shading to blood and it glows in the dark. 2SPOOKY4ME

immutable ushort TILE_W=32;
immutable ushort TILE_H=32;
immutable float SCROLL_SPEED=5;

//ALLEGRO_CONFIG* 		cfg;  //whats this used for?
ALLEGRO_DISPLAY* 		al_display;
ALLEGRO_EVENT_QUEUE* 	queue;
ALLEGRO_TIMER* 			fps_timer;
ALLEGRO_TIMER* 			screencap_timer;

bool[256] keyPressed = false;

FONT* 	font1;

void loadResources()	
	{
	font1 = getFont("./data/DejaVuSans.ttf", 18);
	}

alias sample = ALLEGRO_SAMPLE;
alias COLOR = ALLEGRO_COLOR;
alias color = ALLEGRO_COLOR; // sick of pressing space so much!
alias BITMAP = ALLEGRO_BITMAP;
alias bitmap = ALLEGRO_BITMAP;
alias FONT = ALLEGRO_FONT;
alias font = ALLEGRO_FONT;

/// DEBUGGER CHANNEL STUFF
/// - Can any object send to a variety of "channels"?
/// so we only get data from objects marked isDebugging=true,
/// and we can choose to only display certain channels like 
/// movement or finite state machine.

/// Do we need a MAPPING setup? "debug" includes "object,error,info,etc"
enum logChannel : string
	{
	INFO="info",
	ERROR="error",
	DEBUG="debug",
	FSM="FSM"
	}

class pygmentize// : prettyPrinter
	{
	bool hasStreamStarted=false;
	string style="arduino"; // see pygmentize -L for list of installed styles
	string language="SQL"; // you don't necessarily want "D" for console coloring
	// , you could also create your own custom pygments lexer and specify it here
	//see https://github.com/sol/pygments/blob/master/pygments/lexers/c_cpp.py
	
	// this will be "slower" since we're constantly re-running it with all that overhead
	// we might want to do some sort of batch/buffered version to reduce the number
	// of invocations
	string convert(string input)
		{
		stats.swLogging.start();	
		import std.process : spawnProcess, spawnShell, wait;
	/+	auto pid = spawnProcess(["pygmentize", "-l D"],
                        stdin,
                        stdout,
                        logFile);
      +/
		auto pid = spawnShell(`echo "hello(12,12)" | pygmentize -l D`);
		if (wait(pid) != 0)
			writeln("Compilation failed.");

		stats.swLogging.stop();
		stats.nsLogging = stats.swLogic.peek.total!"nsecs"; // NOTE only need to update this when we actually access it in the stats class
	
		return input;
		}

	import std.process : spawnProcess, spawnShell, wait, ProcessPipes, pipeProcess, Redirect;
	ProcessPipes pipes;

	string convert2(string input)
		{
		stats.swLogging.start();	
		import std.process : spawnProcess, spawnShell, wait;

		auto pid = spawnShell(format(`echo "%s" | pygmentize -l %s -O style=%s`, input, language, style));
		if (wait(pid) != 0)
			writeln("Compilation failed.");
			
		stats.swLogging.stop();
		stats.nsLogging = stats.swLogic.peek.total!"nsecs"; // NOTE only need to update this when we actually access it in the stats class
	
		return input;
		}
		
	string convert3(string input)
		{
   		stats.swLogging.start();

		if(!hasStreamStarted)
			{
			hasStreamStarted = true;
			string flags = "-s -l d";
			pipes = pipeProcess(
				["pygmentize", "-s", "-l", language, "-O", format("style=%s", style)],
				 Redirect.stdin);
			// https://dlang.org/library/std/process/pipe_process.html
			}

		pipes.stdin.writeln(input);
		pipes.stdin.flush();
		
		g.stats.number_of_log_entries++;
			
		stats.swLogging.stop();
		stats.nsLogging = stats.swLogic.peek.total!"nsecs"; // NOTE only need to update this when we actually access it in the stats class
	
		return input;
		}

	this()
		{
		}
		
	~this()
		{
		writefln("total stats.nsLogging time", stats.nsLogging);
		writefln("total log entries", stats.number_of_log_entries);
		if(hasStreamStarted)pipes.stdin.close();
		}
	}
/+
interface prettyPrinter
	{
	string convert(string input);
	string convert2(A...)(A input);
	}
+/
class logger
	{
	bool echoToFile=false;
	bool echoToStandard=false; //stdout
	bool usePrettyPrinter=false; //dump to stdout
	bool usePrettyPrinterDirectly=true; // calls printf itself
	pygmentize printer;
	string[] data;
	string logFilePath;
	
	this(){
		printer = new pygmentize();
		logFilePath = "game.log";
		}
	
	void enableChannel(logChannel channel)
		{
		}

	void disableChannel(logChannel channel)
		{
		}
	
	void forceLog(string name, string str) // log without an object attached using a custom name
		{
		// NYI
		}
	
	void log(T)(T obj, string str2)
		{
		if(!obj.isDebugging)return; // If the object isn't set to debug, we ignore it. So we can just set debug flag at will to snoop its data.
		if(echoToStandard)
			writeln(str2);
		if(usePrettyPrinter)
			writeln(printer.convert3(str2));
		if(usePrettyPrinterDirectly)
			printer.convert3(str2);
		}	

	void logB(T, V...)(T obj, V variadic) /// variadic version
		{
//		import std.traits;

//		pragma(msg, typeof(variadic)); // debug
		if(echoToStandard)
			{
			foreach(i, v; variadic) // debug
				writeln(variadic[i]); // debug
			}
			
		if(usePrettyPrinterDirectly)
			printer.convert3(format(variadic[0], variadic[1..$]));
		}
	}
	
logger log3;

void testLogger()
	{
	writeln("start------------------");
	log3 = new logger;
//	unit u = new unit(0, pair(1, 2), pair(3, 4), g.grass_bmp);
//	u.isDebugging = true;
//	log3.logB(u, "guy died [%d]", 23);
//	log3.log(u, "word(12, 15.0f)");
	writeln("end--------------------");
	}

/// An "index" pair. A pair of indicies for referencing an array
/// typically going to be converted 
struct ipair
	{
	int i, j;

	this(int _i, int _j)
		{
		i = _i;
		j = _j;
		}

//	this(T)(T[] dim) //multidim arrays still want T[]? interesting
	//	{
	//	}

	this(ipair p)
		{
		i = p.i;
		j = p.j;
		}

	this(ipair p, int offsetx, int offsety)
		{
		i = p.i + offsetx;
		j = p.j + offsety;
		}

	// WARNING: take note that we're using implied viewport conversions
	this(pair p)
		{
		// this is ROUNDING THE INTEGER DOWN. (or the other one)
//		alias v=IMPLIED_VIEWPORT; // wait this isn't used???
//		this = ipair(cast(int)p.x/TILE_W, cast(int)p.y/TILE_H);
//		this = ipair(cast(int)lround(p.x/cast(float)TILE_W), cast(int)lround(p.y/cast(float)TILE_H));
		float x, y;
//		writeln("going from ", p);
		if(p.x < 0 )x = ceil(p.x) - 31;// FIXME. TODO. THIS WORKS But do we UNDERSTAND IT ENOUGH?
		if(p.y < 0 )y = ceil(p.y) - 31;
		if(p.x >= 0)x = floor(p.x);
		if(p.y >= 0)y = floor(p.y);

		this = ipair(cast(int)(x/cast(float)TILE_W), cast(int)(y/cast(float)TILE_H));
//		writeln("going to ", this);
		}

	this(pair p, float xOffset, float yOffset)
		{
//		alias v=IMPLIED_VIEWPORT; // wait this isn't used???
//		writeln("  going from ", p, " ", xOffset, " ", yOffset);
		float x, y;
		if(p.x + xOffset < 0 )x = ceil(p.x + xOffset) - 31; // FIXME. TODO. THIS WORKS But do we UNDERSTAND IT ENOUGH?
		if(p.y + yOffset < 0 )y = ceil(p.y + yOffset) - 31;
		if(p.x + xOffset >= 0)x = floor(p.x + xOffset);
		if(p.y + yOffset >= 0)y = floor(p.y + yOffset);

		this = ipair(cast(int)(x/cast(float)TILE_W), cast(int)(y/cast(float)TILE_H));
//		writeln("  going to ", this);
		}

	this(T)(T obj, float xOffset, float yOffset)
		{
	//	alias v=IMPLIED_VIEWPORT; // wait this isn't used???
		this = ipair(cast(int)(obj.pos.x+xOffset)/TILE_W, cast(int)(obj.pos.y+yOffset)/TILE_H);
		}
	}

struct apair
	{
	float a; /// angle
	float m; /// magnitude
	} // idea: some sort of automatic convertion between angle/magnitude, and xy velocities?

struct rpair // relative pair. not sure best way to implement automatic conversions
	{
	float rx; //'rx' to not conflict with x/y duct typing.
	float ry;
	}

struct pair
	{
	float x;
	float y;

	bool opEquals(int val) // what about float/double scenarios?
		{
		assert(val == 0, "Did you really mean to check a pair to something other than 0 == 0,0? This should only be for velocity pairs = 0");
		if(x == val && y == val)
			{
			return true;
			}
		return false;
		}
	
	void opAssign(int val)
		{
		assert(val == 0, "Did you really mean to set a pair to something other than 0,0? This is an unlikely case.");
		x = cast(float)val;
		y = cast(float)val;
		}

	void opAssign(apair val) // for velocity vectors
		{
		x = cos(val.a)*val.m;
		y = sin(val.a)*val.m;
		}
	 
	auto opOpAssign(string op)(pair p)
		{
		static if(op == "+=")
		{
			pragma(msg, "+= THIS HASNT BEEN VERIFIED");
			x += p.x;
			y += p.y;
			return this;
		}else static if(op == "-=") 
		{
			
		}else static if(op == "+" || op == "-")
		{
			pragma(msg, op);
			mixin("x = x "~op~" p.x;");
			mixin("y = y "~op~" p.y;");
			return this;
		}
		else static assert(0, "Operator "~op~" not implemented");
			
		}
	
	/+
	//https://dlang.org/spec/operatoroverloading.html
    // this ~ rhs
	T opBinary(string op)(T rhs)		// add two pairs
		{
		static if (op == "+") 
			{
			pragma(msg, "hello");
			return pair(this, rhs.x, rhs.y);
			}
//		else static if (op == "-") return data - rhs.data;
		else static assert(0, "Operator "~op~" not implemented");
		}	
	
	// http://ddili.org/ders/d.en/operator_overloading.html
    auto opOpAssign(string op)(pair p) 
		if(op =="+=" || op == "-=")
		{
			pragma(msg, "hello2");
        //mixin("ptr"~op~"i;");
//        ptr += p;
		return this; 
		}
	+/
	this(T)(T t) //give it any object that has fields x and y
		{
		x = t.x;
		y = t.y;
		}

	this(T)(T t, float offsetX, float offsetY)
		{
		x = t.x + offsetX;
		y = t.y + offsetY;
		}
	
	this(int _x, int _y)
		{
		x = to!float(_x);
		y = to!float(_y);
		}

	this(float _x, float _y)
		{
		x = _x;
		y = _y;
		}

	this(apair val)
		{
		x = cos(val.a)*val.m;
		y = sin(val.a)*val.m;
		}
	}

	
alias tile=ushort;

struct frameStats_t
	{	
	ulong[2] number_of_drawn_units=0;
	ulong[2] number_of_drawn_particles=0;
	ulong[2] number_of_drawn_structures=0;
	ulong[2] number_of_drawn_asteroids=0;
	ulong[2] number_of_drawn_bullets=0;
	ulong[2] number_of_drawn_dudes=0;
/+
	ulong number_of_drawn_units_clipped=0;
	ulong number_of_drawn_particles_clipped=0;
	ulong number_of_drawn_structures_clipped=0;
	ulong number_of_drawn_asteroids_clipped=0;
	ulong number_of_drawn_bullets_clipped=0;
	ulong number_of_drawn_dudes_clipped=0;+/
	}

struct statistics_t
	{
	ulong number_of_log_entries=0;
	frameStats_t frameStats;	// per frame statistics, array: [0] nonclipped stast, [1] is for clipped units
	alias frameStats this;
	
	ulong fps=0;
	ulong frames_passed=0;
	
	StopWatch swLogic;
	StopWatch swDraw;
	StopWatch swLogging; //note this is a CULMULATIVE timer
	float nsLogic;  // FIXME why is only one named milliseconds
	float nsDraw;
	float nsLogging;
	
	void reset()
		{ 
		// - NOTE: we are ARE resetting these for each viewport so 
		// it CAN be called more than one time a frame!
		// - note we do NOT reset fps and frames_passed here as
		// they are cumulative or handled elsewhere.
		frameStats = frameStats.init; // damn this is easy now!
		}
	}

statistics_t stats;

int mouse_x = 0; //cached, obviously. for helper routines.
int mouse_y = 0;
int mouse_lmb = 0;
int mouse_in_window = 0;
