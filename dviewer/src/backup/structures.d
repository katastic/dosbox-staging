import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;
import allegro5.allegro_color;

import g;
import viewportsmod;
import objects;
import helper;
import turretmod;
import particles;
import mapsmod;
import bulletsmod;
import graph;

import std.math : cos, sin, PI;
import std.stdio;
import std.random;
import std.datetime;
import std.datetime.stopwatch : benchmark, StopWatch, AutoStart;

class tower : structure
	{
	this(pair _pos, int teamIndex)
		{
		immutable int FIRE_COOLDOWN = 10;
		super(_pos, teamIndex, g.bmp.potion);
		primary.setMax(FIRE_COOLDOWN);
		}		
		
	// acquire range could be slightly closer than tracking range (hysterisis)
	bool isTracking = false;
	immutable float TRACKING_RANGE = 200;
	unit myTarget;

	void setTarget(unit u)
		{
		myTarget = u;
		isTracking = true;
		}
	
	bool isTargetInRange(unit u)
		{
		if(u !is null && u.isDead != true && distanceTo(this, u) < TRACKING_RANGE)
			{
			return true;
			}
		return false;
		}
		
	override void onTick()
		{
		super.onTick();
		// Firing pattern mechanic possibilities (for when multiple players exist)
		// - fire only at first person in list (simple) [strat: whoever isn't that player, fight] [ALWAYS FAVORS one player which is bad.]
		// - fire at each person in order					[strat: Spread DPS across players]
		// - fire SAME RATE, but at AS MANY PLAYERS exist.	[DPS increases with players in range]
		// -> fire at FIRST PERSON to be targetted until we no longer have that target in range. [strat: grab aggro, others fight it.]
	//	primary.onTick(); // shouldn't this be on unit?
		
		if(!isTracking)
			{
			foreach(u; g.world.units)
				{
				if(u !is this && u.myTeamIndex != this.myTeamIndex && distanceTo(u, this) < 200 && primary.isReadySet()) // is ready set must come after, as it MUTATES too!
					{
					setTarget(u);
					break;
					}
				}
			}else{
			if(!isTargetInRange(myTarget))
				{
				isTracking = false;
				}else{
				if(primary.isReadySet())
					{
					pair v = apair(angleTo(myTarget, this), 15);
					g.world.bullets ~= new bullet(this.pos, v, angleTo(myTarget, this), yellow, 0, 100, this, 0);
					}
				}
			}
		}
	}

class spawner : structure
	{
	this(pair _pos, int teamIndex)
		{
		super(_pos, teamIndex, g.bmp.fountain);
		immutable int FIRE_COOLDOWN = 120; //3 or 120;
		primary.setMax(FIRE_COOLDOWN);
		}

	void spawnDude()
		{
//		writeln("SPAWNING DUDE");
		g.world.units ~= new soldier(this.pos, g.world.atlas); // FIXME. THIS SHOULD CRASH but it's not
		} 

	override void onTick()
		{
		super.onTick();
		if(primary.isReadySet())
			{
			spawnDude();
			}
		}
	}

class structure : unit
	{	
	this(pair _pos, int teamIndex, ALLEGRO_BITMAP* b)
		{
		super(0, _pos, pair(0,0), b);
		myTeamIndex = teamIndex; //must come after constructor. FIXME. PUT IN CONSTRUCTOR
		}

	override bool draw(viewport v) // how is this different than normal?
		{
		drawCenteredBitmap(bmp, vpair(this.pos), 0);
		return true;
		}
		
	override void onTick() // how is this different than normal unit?
		{
		primary.onTick(); 
		if(cstats.hp <= 0){isDead = true; }
		}
	}
