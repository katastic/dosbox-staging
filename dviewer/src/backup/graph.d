import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;
import allegro5.allegro_color;

import g;
import helper;
import viewportsmod;

import std.format : format;
import std.stdio : writeln;
import std.conv : to;
import std.string : toStringz;

// what if we want timestamps? Have two identical buffers, one with X
// and one with (T)ime? (not to be confused with T below)
class circularBuffer(T, size_t size)
	{
	T[size] data; 
 	int index=0;
	bool isFull=false;
	int maxSize=size;
	
	/* note:
	if 'data' is a static array it causes all kinds of extra problems
	 because static arrays aren't ranges so magic things like maxElement
	 fail.
	 
	but it's its dynamic, now its on the heap. We're only allocating once
	but it's still kinda bullshit.
	
	but then we have to "manage" an expanding array even though its not
	going to expand so the appender has to deal with the case of growing
	until it hits max size. which is also bullshit.
	
	
	should only do this once. call:
	*/
	T cachedMin;
	T cachedMax;
	T cachedAverage;
	
	void updateCachedValues()
		{
		import std.traits : mostNegative;
		import std.math.traits : isNaN;
		int averageCount = size;
		T maxSoFar = to!T(mostNegative!T);
		T minSoFar = to!T(T.max);
		T sumSoFar = 0;
		for(int i = 0; i < size; i++) //fixme : is this running through all nan values??
			{
			if(data[i] > maxSoFar)maxSoFar = data[i]; 
			if(data[i] < minSoFar)minSoFar = data[i];
			if(!data[i].isNaN)
				{
				sumSoFar += data[i];
				}else{
				averageCount--;
				}
			}
		cachedMin = minSoFar;
		cachedMax = maxSoFar;
		cachedAverage = sumSoFar / averageCount;
		}
/*
    T maxElement()
		{
		import std.traits : mostNegative;
		T maxSoFar = to!T(mostNegative!T);
		for(int i = 0; i < size; i++)
			{
			if(data[i] > maxSoFar)maxSoFar = data[i]; 
			}
		return maxSoFar;
		}
		
    T minElement()
		{
		T minSoFar = to!T(T.max);
		for(int i = 0; i < size; i++)
			{
			if(data[i] < minSoFar)minSoFar = data[i]; 
			}
		return minSoFar;
		}
*/
    T opApply(scope T delegate(ref T) dg)
		{ //https://dlang.org/spec/statement.html#foreach-statement
			//http://ddili.org/ders/d.en/foreach_opapply.html
        foreach (e; data)
			{
            T result = dg(e);
            if (result)
                return result;
			}
        return 0;
		}
		
	void addNext(T t)
		{
		index++;
		if(index == data.length)
			{
			index = 0; isFull = true;
			}
		data[index] = t;
		}
	}
	
/// Graph that attempts to automatically poll a value every frame
/// is instrinsic the right name?
/// We also want a variant that gets manually fed values
/// This one also will (if maxTimeRemembered != 0) not reset the "zoom" or y-scaling
/// for a certain amount of time after the 
///
/// Not sure if time remembered should be in terms of individual frames, or, 
/// in terms of "buffers" full. Because a longer buffer, with same frames, will
/// last a shorter length and so what's right for one buffer, could be not enough
/// for a larger one.
///
/// Also warning: Make sure any timing considerations don't expect DRAWING to be
/// lined up 1-to-1 with LOGIC. Draw calls may be duplicated with no new data, or 
/// skipped during slowdowns.

/*
	how do we support multiple datasources of different types? Have we gone about this
	the wrong way? How about simply accepting all datasources and simply converting them
	to float? In addition to simplicity, we can also now accept multiple datasources.
		EXCEPT. while it's easy to support a manual "pushBackData(T)(T value)" function
		is there a way to mark datasources and still have it convert them? Doesn't that
		require some method of storing multiple different data types? I mean all datatypes
		in D inherit from [Object], right? Is that a starting point?

	also what about new features in inherited modified versions of graph?
		multigraph   - figuring this out templates wise.
		coloredgraph - color a line differently above or below a datum ("redlining")
		?			 - filled solid drawing
		?			 - multicolored solid filled graph (showing how much percentage each is)
		?			 - peak detection?
*/
class intrinsicGraph(T)
	{
	string name;
	bool isScaling=true;  // NYI, probably want no for FPS
	bool isTransparent=false; // NYI, no background. For overlaying multiple graphs (but how do we handle multiple drawing multiple min/max scales in UI?)
	bool doFlipVertical=false; // NYI, flip vertical axis. Do we want ZERO to be bottom or top. Could be as easy as sending a negative scaling value.
	float x=0,y=300;
	int w=400, h=100;
	COLOR color;
	BITMAP* buffer;
	T* dataSource; // where we auto grab the data every frame
	circularBuffer!(T, 400) dataBuffer; //how do we invoke the constructor?
	float scaling = 1.0; /// scale VALUES by this for peeking numbers with higher granulaity (nsecs to view milliseconds = 1_000_000)

	// private data
// 	private T max=-9999; //READONLY cache of max value.
// 	private T min=-9999; //READONLY cache of max value.
 	private float scaleFactor=1.00; //READONLY set by draw() every frame.
 	private int maxTimeRemembered=600; // how many frames do we remember a previous maximum. 0 for always update.
 	private T previousMaximum=0;
 	private T previousMinimum=0;
	private int howLongAgoWasMaxSet=0;
 	
	this(string _name, ref T _dataSource, float _x, float _y, COLOR _color, float _scaling=1)
		{
		scaling = _scaling;
		name = _name;
		dataBuffer = new circularBuffer!(T, 400);
		dataSource = &_dataSource;
		color = _color;
		x = _x;
		y = _y;
		}

	void draw(viewport v)
		{
		// TODO. Are we keeping/using viewport? 
		// We'd have to know which grapsh are used in which viewport
		al_draw_filled_rectangle(x + v.x, y + v.y, x + w + v.x, y + h + v.y, COLOR(0,0,0,.75));

		// this looks confusing but i'm not entirely sure how to clean it up
		// We need a 'max', that is cached between onTicks. But we also have a tempMax
		// where we choose which 'max' we use
		
		T tempMax = dataBuffer.cachedMax;
		T tempMin = dataBuffer.cachedMin;
		howLongAgoWasMaxSet++;
//		if(howLongAgoWasMaxSet <= maxTimeRemembered) DISABLED
		if(tempMax < previousMaximum)
			{
			tempMax = previousMaximum;
			}else{
			previousMaximum = tempMax;
			howLongAgoWasMaxSet = 0;
			}
		if(tempMin > previousMinimum)
			{
			tempMin = previousMinimum;
			}else{
			previousMinimum = tempMin;
			}
		import std.math : abs;
		if(tempMax == tempMin)tempMax++;
		scaleFactor = h/(tempMax + abs(tempMin)); //fixme for negatives. i think the width is right but it's still "offset" above the datum then.
//		al_draw_scaled_line_segment(pair(this), dataBuffer.data, scaleFactor, color, 1.0f);
		al_draw_scaled_indexed_line_segment(pair(this), dataBuffer.data, scaleFactor, color, 1.0f, dataBuffer.index, blue);

		al_draw_text(g.font1, white, x, y, 0, format("%s ~= %.1f",name, dataBuffer.cachedAverage/scaling).toStringz);
		al_draw_text(g.font1, white, x + w - 64, y, 0, format("%.1f",dataBuffer.cachedMin/scaling).toStringz);
		al_draw_text(g.font1, white, x + w - 64, y+h-g.font1.h, 0, format("%.1f",dataBuffer.cachedMax/scaling).toStringz);
		al_draw_text(g.font1, white, x     + 64, y+h-g.font1.h, 0, format("%.1f",dataBuffer.data[dataBuffer.index]/scaling).toStringz); /// current index / value
		}
		
	void onTick()
		{
	//	max = dataBuffer.maxElement; // note: we only really need to scan if [howLongAgoWasMaxSet] indicates a time we'd scan
	//	min = dataBuffer.minElement; // note: we only really need to scan if [howLongAgoWasMaxSet] indicates a time we'd scan
		dataBuffer.updateCachedValues();
		dataBuffer.addNext(*dataSource);
		}
	}
	
