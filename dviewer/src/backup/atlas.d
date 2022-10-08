import helper;
import g;

import std.stdio;
import std.conv;
import std.json;
import std.file;

import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;

struct atlas_t
	{
	bool isHidden=false;
//	meta_t*	[] meta;
//	meta_t	[16*25] meta;
	bool [16*25] isPassable=true;
	BITMAP* [] data;
	alias data this;
	BITMAP* atl;
	int w=16;
	int h=25;

	// Editing the metadata functions
	// ---------------------------------------------------------------
	int currentCursor=0;
	void changeCursor(int relValue)
		{
		if( (cast(short)currentCursor + relValue >= 0) 
			&& 
			currentCursor + relValue <= data.length)
			{
			currentCursor += relValue;
			writeln(currentCursor.stringof, " = ", currentCursor);
			}			
		}
		
	void toggleIsPassable()
		{
		writeln("Toggling isPassable for ", currentCursor, " = ", isPassable[currentCursor]);
		isPassable[currentCursor] = !isPassable[currentCursor];		
		}
		
	//https://forum.dlang.org/post/t3ljgm$16du$1@digitalmars.com
	//big 'ol wtf case.
	void rawWriteValue(T)(File file, T value)
		{
		file.rawWrite((&value)[0..1]);
		}

	JSONValue map_in_json_format;

	void saveMeta(string path="./data/maps/meta.map")
		{
		writeln("save META map");
		File f = File(path, "w");

			//map_in_json_format = parseJSON("{ \"taco\":\"boo\"}");

		map_in_json_format.object["width"] = 50;
		map_in_json_format.object["height"] = 50;
		map_in_json_format.object["isPassable"] = JSONValue( isPassable ); 
	//		writeln(map_in_json_format);

		f.write(map_in_json_format.toJSON(false));
		f.close();
			
//		auto f = File(path, "w");
	//	rawWriteValue(f, meta);
		//https://forum.dlang.org/post/mailman.113.1330209587.24984.digitalmars-d-learn@puremagic.com
		}

	void loadMeta(string path="./data/maps/meta.map")
		{
		writeln("LOADING META MAP");
		
		string str = std.file.readText(path);
	//	writeln(str);
		map_in_json_format = parseJSON(str);
		writeln(map_in_json_format);

		auto t = map_in_json_format;

//		int width = to!int(t.object["widthl"].integer);
//		int height = to!int(t.object["height"].integer);
//		writeln(width, " by ", height);
		writeln("------");
		writeln(t.object["isPassable"].array);
	
		foreach(size_t i, ref r; t.object["isPassable"].array)
			{
//			writeln(i, r);
			isPassable[i] = to!bool(r.boolean); //"integer" outs long. lulbbq.
			}
			
//		auto read = File(path).rawRead(meta[]);
		}

	// -----------------------------------------------------------------------

	BITMAP* canvas;
	void drawAtlas(float x, float y)
		{
		import g : TILE_W, TILE_H;
		assert(canvas !is null);
		al_set_target_bitmap(canvas);
		al_draw_filled_rectangle(0, 0, 0 + atl.w-1, 0 + atl.h-1, ALLEGRO_COLOR(.7,.7,.7,.7));
		al_draw_bitmap(atl, 0, 0, 0);

		{
		int idx = 0;
		int i = 0;
		int j = 0;
		
		do{
			if(i >= atl.w/TILE_W)
				{
				i=0;
				j++;
				}
			if(j >= atl.h/TILE_H)break;
			if(idx >= w*h-1)break;

//			if(isPassable[idx] == false && g.selectLayer) //we only draw this for the primary layer
				{
				al_draw_filled_rectangle(i*TILE_W + 16, j*TILE_H + 16, i*TILE_W + 32, j*TILE_H + 32,COLOR(1,0,0,.5));
				}
			i++;
			idx++;
			}while(true);
		}

		{
		int idx = 0;
		float x2 = 0;
		float y2 = 0;
		
		do{
			if(idx == currentCursor)break;
			idx++;
			x2+=TILE_W;
			if(x2 >= atl.w)
				{
				x2 = 0;
				y2 += TILE_W;
				}
			}while(true);
		al_draw_rectangle(0 + x2, 0 + y2, 0 + x2 + TILE_W-1, 0 + y2 + TILE_H-1, ALLEGRO_COLOR(1,0,0,1), 3);
		}
		
		al_reset_target();
		immutable float SCALE = 0.75;
		al_draw_scaled_bitmap2(canvas, x, y, SCALE, SCALE);
		
		}

	void load(string filepath)
		{
		writeln("loading atlas at ", filepath);
		atl = getBitmap(filepath);
		//assert(atl != null, "ATLAS " ~ filepath ~ " NOT FOUND/LOADABLE");
		
		int width = atl.w;
		int height = atl.h;
		
		assert(width % 32 == 0, "ATLAS ISNT 32-byte ALIGNED. ZEUS IS FURIOUS."); 
		
		int z = 0;
		for(int j = 0; j < h; j++) //note: order important
		for(int i = 0; i < w; i++)
			{
//			writeln("i, j, z = ", i, " ", j, " ", z);
			BITMAP* b = al_create_sub_bitmap(atl, TILE_W*i, TILE_H*j, TILE_W, TILE_H);
			assert(b != null);
			data ~= b;
			
			if(z == 1 || z == 9)
				{
				isPassable[z] = false;
				}else{
				isPassable[z] = true;
				}
			z++;
			}
//		writeln("meta.length = ", meta.length);
		writeln("data.length = ", data.length);

		if(canvas) // just in case this gets called twice
			{
			al_destroy_bitmap(canvas); 
			}
		canvas = al_create_bitmap(atl.w, atl.h);
		assert(canvas !is null);
		}
	}
