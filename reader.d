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
	
	void scanMinMax()   /// for max address, we ADD 1 (for word writes) and ADD 2 (for dword writes) since that's the last byte they touch?
		{
		foreach(op; ops)
			{
			if(op.address < minAddress)minAddress = op.address;
			if(op.address+(op.bytes-1) > maxAddress)maxAddress = op.address+(op.bytes-1);
			}
		}
	}


void main()
	{
	// for each frame, track the min and max, address touched.

	frame[] frames;
	bool firstRun=true;
	int currentExpectedFrame = -1024;
    auto file = File("output2.txt", "r");
    frame currentFrame;
    foreach (record; file.byLine.joiner("\n").csvReader!(Tuple!(
			int, string, int, int, int,
			string, string, int, int, int, 
			int, int, int)))
		{
			writefln("%d,%s,%d,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d",
				record[0], record[1], record[2], record[3], record[4], record[5],
				record[6], record[7], record[8], record[9], record[10], record[11],
				record[12]);
		
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
				if(o.bytes == 1) {o.data[0] = record[9];}
				if(o.bytes == 2) {o.data[0] = record[9]; o.data[1] = record[10];}
//				if(o.bytes == 4) {o.data[0] = record[10]; o.data[1] = record[11]; o.data[2] = record[12]; o.data[3] = record[13];}
				currentFrame.ops ~= o;
				}
		}
		
	frames ~= currentFrame; // last one onto the pile
	int totalOps=0;
	
	foreach(f; frames)
		{
		writeln("FRAME ", f.frameNumber, " (", f.ops.length, " draw ops) ---------------------------------------------------------------");
		totalOps += f.ops.length;
		foreach(o; f.ops)
			{
			writeln("    ", o);
			}
		}
		
	writeln("total frames: ", frames.length);
	writeln("total ops: ", totalOps);

	// from https://dlang.org/phobos/std_csv.html
	}
