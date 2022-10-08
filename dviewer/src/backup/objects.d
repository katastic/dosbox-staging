import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;
import allegro5.allegro_color;

import std.conv;
import std.random;
import std.stdio;
import std.math;
import std.string;
import std.algorithm : remove;
import std.traits;

import g;
import helper;
import viewportsmod;
import particles;
import guns;
import turretmod;
import bulletsmod;
import mapsmod;
import blood;
import structures;
import worldmod;
/+
charStats thoughts:
	- they used a separate class for archmage. Instead, we could use multiple cstats array for evolutions. 
		However, their way might be easier to have "different abilities" as opposed to just new ones like other classes.
		but it'd be nice if other classes had promotions too. (think mm6, they also scale stats differently in mm6)		

i haven't made classes for
	- thief
	- orc, bigOrc
	- barbarian
	
honestly those classes were pretty crap unless i missed something. thief was more of a sapper/bomber.

+/
	
//immutable float FALL_ACCEL = .1;
immutable float WALK_SPEED = .30;
immutable float JUMP_SPEED = 5;
immutable float BULLET_SPEED = 5;

struct cooldown /// todo: find better name
	{
	alias value this;
	int value;
	int max;

	this(int setval)
		{
		max = setval;
		value = setval; // should we add +1 for initial ontick subtraction?
		}
		
	void setMax(int val)
		{
		value = val;
		max = val;
		}
		
	bool isReady()
		{
		if(value > 0)return false;
		return true;
		}

	bool isReadySet() /// if ready, return true and reset to max so caller can act on it
		{
		if(value > 0)return false;
		value = max;
		return true;
		}
	
	void onTick()
		{
		if(value > 0)value--;
		}
	
	void set(int val)
		{
		value = val;
		}
	}

struct charStats //character stats, 'cstats' in object?
	{
	int str=10;
	int dex=10;
	int con=10;
	int intel=10; // can't use int, since, you know, 'int'
	int armor=10; // glad
//	int personality; // might and magic: mana for druids.
//  int speed=10; // derived from DEX?
// other stats? what would charisma be for?   luck?

	int hp=100; 		// put health here
	int hpMax=100; 		// 
	int mp=100; 		// 
	int mpMax=100; 	// 
	
	// strMod	- we could have temporary modifiers here too, and at worst, they get reset when you leave a map.
	// or we could do some sort of exotic tag based method where each tag has a time cooldown and cure spells 
	// can search tags to remove them.

	int xp=0;
	int level=0; // derived from xp? or cached
	
	// note we may want to have different values/getters
	// because we can return the APPLIED (or different word) str/con/dex/int which includes bonuses.
	// as opposed to their specific character ones.
	// certain stats will depend on their BASE stats, and others depend on their MODIFIED ones.
/+
	supposedly, in mm6, stats are "weighted". the more you gain as you go up, the less you get for each gain in stats to keep you from becoming a god.

	stat	diff	n
	1				0
	3		2		1
	5		2		2
	7		2		3
	9		2		4
	11		2		5
	13		2		6
	15		2		7...
	17		2
	19		2
	21		2
	25		3
	30		5
	35		5
	40		5
	50		10
	75		25
	100		25
	125		25		18
	150		25
	175		25
	200		25				

	why the hell aren't these tables identical? Is the pottsland starting at 0 instead of -6 or whatver?

	1		-6
	3		-5
	5		-4
	7		-3
	9		-2
	11		-1
	13		0
	15		1
	17		2
	19		3
	21		4
	25		5
	30		6
	35		7
	40		8
	50		9
	75		10
	100		11
	125		12
	150		13
	175		14
	200		15
	225		16
	250		17
	275		18
	300		19
	350		20	
	400		25	(note skipping 5 here on)
	500		30

	https://www.angelfire.com/nt/bones/
	http://www.pottsland.com/mm6/attributes2.shtml
	https://www.gog.com/forum/might_and_magic_series/limit_to_benefit_of_stats_in_mm6
+/
	}

enum DIR
	{
		UP = 0,	// some only have 1 direction and stop here.
		DOWN,
		LEFT,
		RIGHT,	// some only have 4 (U,D,L,R) directions and stop here.
		UPLEFT,
		UPRIGHT,
		DOWNRIGHT,
		DOWNLEFT,
	}

ipair[] ghost_coords = [ipair(0,0), ipair(72,0), ipair(144,0), ipair(217,0), 
					      ipair(288,0), ipair(72+288,0), ipair(144+288,0), ipair(217+288,0)];

ipair[] archer_coords = [ipair(0,70), ipair(72,70), ipair(144,70), ipair(217,70),
						ipair(288,70), ipair(72+288,70), ipair(144+288,70), ipair(217+288,70)];

ipair[] elf_coords = [ipair(0,144), ipair(72,144), ipair(144,144), ipair(217,144),
						ipair(288,144), ipair(72+288,144), ipair(144+288,144), ipair(217+288,144)];

ipair[] soldier_coords = [ipair(0,360), ipair(72,360), ipair(144,360), ipair(217,360), 
					      ipair(288,360), ipair(72+288,360), ipair(144+288,360), ipair(217+288,360)];

ipair[] mage_coords = [ipair(0,396), ipair(72,396), ipair(144,396), ipair(217,396),
						ipair(288,396), ipair(72+288,396), ipair(144+288,396), ipair(217+288,396)];
						
class atlasHandler
	{
	BITMAP* data;
	BITMAP* dataOutlined;
		
	this()
		{
		data = getBitmap("./data/extra/gauntlet.png");
		writeln("building outline for atlas");
		dataOutlined = buildOutline(data);
		assert(data !is null);
		assert(dataOutlined !is null);
		}
		
	/// Note: this is run outside of animations because we don't want in run every single time a new object is spawned. 
	BITMAP* buildOutline(BITMAP* b)	// TODO BUG. what if outline needs to be OUTSIDE the atlas bitmap confines? [we need to make atlas +1 on each side, and then UPDATE the subbitmap coordinates +1 accordingly! That, or make the normal one also +1 for the hell of it.]
		{
		assert(b !is null);
		BITMAP* output = al_create_bitmap(b.w, b.h);
		COLOR outlineColor = white; 
	//		COLOR clearColor = COLOR(0,0,0,1);

		bool isTransparent(BITMAP* bi, ipair p)
			{
			COLOR c = getPixel(bi, p);
	//			writefln("%s @ %s", c, p);
			if(c.a.isClose(0))		/// looks like internally it would be 0,0,0,0 for transparent
				{
				return true;
				}
			return false;
			}
		
		bool isInside(BITMAP* _b, ipair p)
			{
			if(p.i >= 0 && p.j >= 0)
			if(p.i < _b.w && p.j < _b.h)
				return true;
			return false;
			}
			
		void doOutline(BITMAP* _bi, ipair p)
			{
			if(isInside(_bi, p) && isTransparent(_bi, p)){al_put_pixel(p.i, p.j, outlineColor);}
			}
			
		void checkDirections(BITMAP* bi, BITMAP* bo, ipair p) /// NOTE: Assumes target bitmap is set and locked
			{
			if(isInside(bi, p))
				if(!isTransparent(bi, p)) /// For every 'real' pixel, check for borders
					{
//					al_put_pixel(p.i, p.j, getPixel(bi, p)); // draw original pixels
					doOutline(bi, ipair(p,-1, 0));
					doOutline(bi, ipair(p, 1, 0));
					doOutline(bi, ipair(p, 0,-1));
					doOutline(bi, ipair(p, 0, 1));
					}else{
	//				al_put_pixel(p.i, p.j, getPixel(bi, p));
					}
			}
		
		al_set_target_bitmap(output); 
		al_lock_bitmap(b, al_get_bitmap_format(b), ALLEGRO_LOCK_READONLY);			
		al_lock_bitmap(output, al_get_bitmap_format(output), ALLEGRO_LOCK_WRITEONLY);
		for(int i = 1; i < b.w; i++) 
			for(int j = 1; j < b.h; j++)
			{
			checkDirections(b, output, ipair(i,j));
			}
		al_unlock_bitmap(b);
		al_unlock_bitmap(output);
		al_reset_target();
		
		return output;
		}
	}

class animation
	{
	// do we want/care to reset walk cycle when you change direction? 
	int numDirections; 
	int numFrames=2;
	int index = 0; /// frame index
	bool usesFlippedGraphics = false; /// NYI. use half the sideways graphics and flips them based on direction given. Usually meaningless given RAM amounts.

	bool isOutlined = false; // should this be a state, or simply a different draw function (state is in the object itself)
	bool isOutlineOnly = false; 

	BITMAP*[2][DIR.max] bmps;
	BITMAP*[2][DIR.max] bmpsOutlined;

	this(int _numFrames, ipair[] coordinates, atlasHandler atlas)
		{
		assert(atlas !is null);
		assert(atlas.data !is null);
		assert(atlas.dataOutlined !is null);
		
		parseMap3(coordinates, atlas);
		}

	void parseMap3(ipair[] pt, atlasHandler atlas)
		{
		assert(atlas !is null);
		int w = 32;
		int h = 32;
		int wo = w + 4; // width plus padding offset
				
		bmps[DIR.UP][0] = al_create_sub_bitmap(atlas.data, pt[0].i, pt[0].j, w, h);
		bmps[DIR.RIGHT][0] = al_create_sub_bitmap(atlas.data, pt[1].i, pt[1].j, w, h);
		bmps[DIR.DOWN][0] = al_create_sub_bitmap(atlas.data, pt[2].i, pt[2].j, w, h);
		bmps[DIR.LEFT][0] = al_create_sub_bitmap(atlas.data, pt[3].i, pt[3].j, w, h);

		bmps[DIR.UP][1] = al_create_sub_bitmap(atlas.data, pt[4].i, pt[4].j, w, h);
		bmps[DIR.RIGHT][1] = al_create_sub_bitmap(atlas.data, pt[5].i, pt[5].j, w, h);
		bmps[DIR.DOWN][1] = al_create_sub_bitmap(atlas.data, pt[6].i, pt[6].j, w, h);
		bmps[DIR.LEFT][1] = al_create_sub_bitmap(atlas.data, pt[7].i, pt[7].j, w, h);
	
		bmpsOutlined[DIR.UP][0] = al_create_sub_bitmap(atlas.dataOutlined, pt[0].i, pt[0].j, w, h);
		bmpsOutlined[DIR.RIGHT][0] = al_create_sub_bitmap(atlas.dataOutlined, pt[1].i, pt[1].j, w, h);
		bmpsOutlined[DIR.DOWN][0] = al_create_sub_bitmap(atlas.dataOutlined, pt[2].i, pt[2].j, w, h);
		bmpsOutlined[DIR.LEFT][0] = al_create_sub_bitmap(atlas.dataOutlined, pt[3].i, pt[3].j, w, h);

		bmpsOutlined[DIR.UP][1] = al_create_sub_bitmap(atlas.dataOutlined, pt[4].i, pt[4].j, w, h);
		bmpsOutlined[DIR.RIGHT][1] = al_create_sub_bitmap(atlas.dataOutlined, pt[5].i, pt[5].j, w, h);
		bmpsOutlined[DIR.DOWN][1] = al_create_sub_bitmap(atlas.dataOutlined, pt[6].i, pt[6].j, w, h);
		bmpsOutlined[DIR.LEFT][1] = al_create_sub_bitmap(atlas.dataOutlined, pt[7].i, pt[7].j, w, h);
		}

	void nextFrame()
		{
		index++;
		if(index == numFrames)index = 0;
		}
		
	bool draw(pair pos, DIR dir) /// implied viewport
		{
		BITMAP *source = bmps[dir][index];
		BITMAP *sourceOutlined = bmpsOutlined[dir][index];
		color outlineColor = white; // how do we handle this verses lighting?
		if(isOnScreen(pos))
			{
				
			if(!g.useLighting)
			{
				if(isOutlineOnly)
					{
					drawCenteredTintedBitmap( sourceOutlined, outlineColor, vpair(pos), 0);
					return true;
					}

				if(isOutlined)drawCenteredTintedBitmap( sourceOutlined, outlineColor, vpair(pos), 0);
				drawCenteredBitmap( source, vpair(pos), 0);
			}else{
				if(isOutlineOnly)
					{
					drawCenteredTintedBitmap( sourceOutlined, outlineColor, vpair(pos), 0);
					return true;
					}

				if(isOutlined)drawCenteredTintedBitmap( sourceOutlined, outlineColor, vpair(pos), 0);
				drawCenteredTintedBitmap( source, getTopShadeTint(g.world.units[0].pos, pos), vpair(pos), 0);				
			}
			return true;
		}else{
			return false;}
		}
	}

class archer : unit
	{
	float spinAngle = 0;
	float SPIN_SPEED = degToRad(10);
	int COOLDOWN_TIME = 30;

	bool isSpinning = false;

	void spin()
		{
		if(!isSpinning && mp > 80)
			{
			mp -= 80; 
			spinAngle = 0;
			isSpinning = true;
			freezeMovement = true;
			}
		}

	override void actionSpecial()
		{
		spin();
		}
		
	override void onTick()
		{
		if(isSpinning)
			{
			writefln("%3.2f", spinAngle);
			immutable int NUM_SHOTS = 10;
			if(fmod(spinAngle,2f*PI/NUM_SHOTS) < .1) // fixme: this needs to be different. divide distance into number of shots, and a total time for action so you can adjust that for balance.
				{
				// fireShot();
				g.world.bullets ~= new bullet( this.pos, pair(apair( spinAngle, BULLET_SPEED)), spinAngle, red, 100, 0, this, 0);
//	this(pair _pos, pair _vel, float _angle, COLOR _c, int _type, int _lifetime, bool _isAffectedByGravity, unit _myOwner, bool _isDebugging)
				writefln("firing shot at %3.2f", spinAngle);
				}
			spinAngle += SPIN_SPEED;
			if(spinAngle > 2*PI){isSpinning = false; freezeMovement = false; spinAngle = 0;}
			}else{
			super.onTick();
			}
		}

	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, archer_coords, atlas);
		}
	}	

class elf : unit
	{
	this(pair _pos, int teamIndex, atlasHandler atlas)
		{	
		super(0, _pos, pair(0, 0), g.bmp.dude);
		myTeamIndex = teamIndex; // TODO put into unit constructor
		anim = new animation(1, elf_coords, g.world.atlas);
		isTreeWalker = true;
		}

	override void actionFire()
		{
		if(primary.isReadySet())
			{
			g.world.bullets ~= new elfBullet( this.pos, pair(apair( toAngle(direction), 10)), toAngle(direction), red, 100, 0, this, 0);
			g.world.bullets[$-1].isForestBullet = true;
			if(isDebugging)g.world.bullets[$-1].isDebugging = true;
			}
		}

	override void actionSpecial()
		{
		if(special.isReadySet())
			{
			immutable int NUM_SHOTS = 16;
			for(float ang = 0; ang < 2*PI; ang += 2*PI/NUM_SHOTS) 
				{
				g.world.bullets ~= new elfBullet( this.pos, pair(apair( ang, BULLET_SPEED)), ang, brown, 100, 0, this, 0);
				g.world.bullets[$-1].isForestBullet = true;
				}
			}
		}

	override void onTick()
		{
		auto ip = ipair(this.pos);
		if(isMapValid(ip) && isForestTile( g.world.map.bmpIndex[ip.i][ip.j]))
			{
			anim.isOutlineOnly = true;
			}else{
			anim.isOutlineOnly = false;
			}
		super.onTick();
		}
	}

class faery : unit
	{
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, ghost_coords, atlas); //fixme
		isFlying = true;
		}
		
	override void actionSpecial()
		{
		if(special.isReadySet())
			{
			immutable int NUM_SHOTS = 16;
			for(float ang = 0; ang < 2*PI; ang += 2*PI/NUM_SHOTS) 
				{
				g.world.bullets ~= new bullet( this.pos, pair(apair( ang, BULLET_SPEED)), ang, red, 100, 0, this, 0);
				}
			}
		}

	override void onTick()
		{
		super.onTick();
		}
	}

class druid : unit
	{
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, ghost_coords, atlas); //fixme
		isFlying = true;
		}
		
	override void actionSpecial()
		{
		if(special.isReadySet())
			{
			}
		}

	override void onTick()
		{
		super.onTick();
		}
	}

class fireElemental : unit
	{
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, ghost_coords, atlas); //fixme
		}
		
	override void actionSpecial()
		{
		if(special.isReadySet())
			{
			immutable int NUM_SHOTS = 16;
			for(float ang = 0; ang < 2*PI; ang += 2*PI/NUM_SHOTS) 
				{
				g.world.bullets ~= new bullet( this.pos, pair(apair( ang, BULLET_SPEED)), ang, red, 100, 0, this, 0);
				}
			}
		}

	override void onTick()
		{
		super.onTick();
		}
	}

class ghost : unit
	{
	this(pair _pos, int teamIndex, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		myTeamIndex = teamIndex; // TODO put into unit constructor
		anim = new animation(1, ghost_coords, atlas);
		isGhost = true;
		}
			
	override void actionSpecial()
		{
		if(special.isReadySet)
			{
			immutable int NUM_SHOTS = 16;
			for(float ang = 0; ang < 2*PI; ang += 2*PI/NUM_SHOTS) 
				{
				g.world.bullets ~= new bullet( this.pos, pair(apair( ang, BULLET_SPEED)), ang, red, 100, 0, this, 0);
				}
			}
		}

	override void onTick()
		{
		super.onTick();
		}
	}

class mage : unit
	{
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, mage_coords, atlas);
		}
		
	int specialCooldownValue = 0;
	int specialCooldown = 60;
	override void actionSpecial()
		{
		if(specialCooldownValue == 0)
			{
			specialCooldownValue = specialCooldown;
			pos.x = uniform!"[]"(0, g.world.map.width*TILE_W-1);
			pos.y = uniform!"[]"(0, g.world.map.height*TILE_H-1);
			}
		}

	override void onTick()
		{
		if(specialCooldownValue > 0)specialCooldownValue--;
		super.onTick();
		}
	}

class skeleton : unit
	{
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, mage_coords, atlas); //fixme
		}

	int specialCooldownValue = 0;
	int specialCooldown = 60;
	override void actionSpecial()
		{
		if(specialCooldownValue == 0)
			{
			// todo. local teleport, finding valid spot.
			specialCooldownValue = specialCooldown;
			pos.x = uniform!"[]"(0, g.world.map.width*TILE_W-1);
			pos.y = uniform!"[]"(0, g.world.map.height*TILE_H-1);
			}
		}
	override void onTick()
		{
		if(specialCooldownValue > 0)specialCooldownValue--;
		super.onTick();
		}
	}

class slimeLarge : unit
	{
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, mage_coords, atlas); //fixme
		}
	}
	
class slimeMedium : unit 
	{	
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, mage_coords, atlas); //fixme
		}
	}

class slimeSmall : unit 
	{	
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, mage_coords, atlas); //fixme
		}
	}

class cleric : unit
	{
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, mage_coords, atlas); //fixme
		}
		
	int specialCooldownValue = 0;
	int specialCooldown = 60;
	float healAmount = 2;
	float healManaCost = 1;
	override void actionSpecial()
		{
		foreach(o; g.world.units)
			{
			if(o.myTeamIndex == this.myTeamIndex && o !is this && distanceTo(o, this))
				{
				if(mp - healManaCost >= 0)
					{
					mp -= healManaCost;
					o.cstats.hp += healAmount;
					clampHigh(o.cstats.hp, o.cstats.hpMax);
					}
				}
			}
		
		// if anyone on my team nearby
		// apply heal
		// reduce mana
		}
	}

class soldier : unit
	{
	float CHARGE_SPEED = 10.0;
	int COOLDOWN_TIME = 30;
	
	this(pair _pos, atlasHandler atlas)
		{
		super(0, _pos, pair(0, 0), g.bmp.dude);
		anim = new animation(1, soldier_coords, atlas);
		}

	override bool draw(viewport v)
		{
		anim.nextFrame();
		return anim.draw(this.pos, direction);
		}
	
	int chargeCooldown=0;
	void charge() // "HUURRRLL"
		{
		if(chargeCooldown == 0 && mp > 80)
			{
			mp -= 80; 
			chargeCooldown = COOLDOWN_TIME;
			freezeMovement = true;
			}
		}
	
	override void onTick()
		{
		if(chargeCooldown) // can't do anything except run forward during charge.
			{
			pos += vel;
			chargeCooldown--;
			if(chargeCooldown == 0)freezeMovement = false;
			return;
			}
		super.onTick();
		// normal stuff
		}
	
	override void actionSpecial()
		{
		charge();
		}

	override void actionUp()
		{
		if(chargeCooldown)return;
		vel = apair(toAngle(DIR.UP), CHARGE_SPEED);
		super.actionUp();
		}
	override void actionDown()
		{
		if(chargeCooldown)return;
		vel = apair(toAngle(DIR.DOWN), CHARGE_SPEED);
		super.actionDown();
		}
	override void actionLeft()
		{
		if(chargeCooldown)return;
		vel = apair(toAngle(DIR.LEFT), CHARGE_SPEED);
		super.actionLeft();
		}
	override void actionRight()
		{
		if(chargeCooldown)return;
		vel = apair(toAngle(DIR.RIGHT), CHARGE_SPEED);
		super.actionRight();
		}
	}

class unit : baseObject /// WARNING: This applies PHYSICS. If you inherit from it, make sure to override if you don't want those physics.
	{
	cooldown primary;
	cooldown special;
		
	charStats cstats;
	animation anim;
	bool isGhost = false;  /// Can fly over anything.
	bool isFlying = false;	/// Can fly through anything bullets can fire through? (wall gratings, etc)
	bool isTreeWalker = false; /// Can walk through tree tiles? Normally I wouldn't 'pollute' a base class with specifics but these are rare and barely invasive.
	/// we could combine these into a single state machine
	
//	float hpMax=100.0; /// Maximum health points
//	float hp=100.0; /// Current health points
	float ap=0; /// armor points (reduced on hits then armor breaks)
	float armor=0; /// flat reduction (or percentage) on damages, haven't decided.
	float mp=100;
	float mpMax=100;
	float manaChargeRate = 2;
	int myTeamIndex=0;
	bool isPlayerControlled=false;
	float weapon_damage = 5;
	bool isFlipped = false; // flip horizontal
	bool freezeMovement = false; /// for special abilities/etc. NOT the same as being frozen by a spell or something like that.
	bool isInvulnerable = false;
	DIR direction;			/// sprite draw direction (up, down, etc)

	int flyingCooldown = -1; // -1 means infinite, potions will set this to a value to tickdown.
	int invulnerabilityCooldown = -1; // -1 means infinite, potions will set this to a value to tickdown.
	
	this(uint _teamIndex, pair _pos, pair _vel, ALLEGRO_BITMAP* b)
		{
		myTeamIndex = _teamIndex; 
		super(_pos, _vel, b);
		//writefln("xy v:xy %f,%f %f,%f", x, y, vx, vy);
		primary.setMax(30);
		special.setMax(30);
		}

	void handlePotions()
		{
		if(flyingCooldown != -1)
			{
			isFlying = true;
			flyingCooldown--;
			if(flyingCooldown == 0)isFlying = false;
			}
		if(invulnerabilityCooldown != -1)
			{
			isInvulnerable = true;
			invulnerabilityCooldown--;
			if(invulnerabilityCooldown == 0)isInvulnerable = false;
			}
		}

	override bool draw(viewport v)
		{
		assert(anim !is null);
		draw_hp_bar(pos.x - bmp.w/2, pos.y - bmp.h/2, v, cstats.hp, cstats.hpMax);
		draw_mp_bar(pos.x - bmp.w/2, pos.y - bmp.h/2 + 5, v, cstats.mp, cstats.mpMax);
		return anim.draw(this.pos, direction);
		}
	
/+	override bool draw(viewport v)
		{
8		if(!isWideInsideScreen(vpair(this.pos), bmp))return false;
		// NOTE we're drawing with "center" being at the bottom of the image.
		drawCenteredBitmap(bmp, vpair(this.pos), isFlipped);
//		if(isDebugging) drawTextCenter(vpair(this, 0, -32), black, "J%1dF%1d V%3.1f,%3.1f", isJumping, isFalling, vx, vy);
		
		if(isPlayerControlled) 
			{
			}
	
		draw_hp_bar(pos.x - bmp.w/2, pos.y - bmp.h/2, v, hp, maxHP);		
		draw_mp_bar(pos.x - bmp.w/2, pos.y - bmp.h/2 + 5, v, mp, maxMP);		
		return true;
		}
+/	
	bool attemptMove(pair offset)
		{
		ipair ip3 = ipair(this.pos, offset.x, offset.y); 
		//writeln("obj ", this.pos, " ", ip3);
		if(isGhost) { this.pos += offset; return true;} 
		if(isFlying)
			{
			// todo: this doesn't allow you to fly through a tile thats not shootable but is walkable (if that exists)
			if(isMapValid(ip3) && isShotPassableTile(g.world.map.bmpIndex[ip3.i][ip3.j]))
				{
				this.pos += offset;
				return true;
				}else{
				return false;
				}
			} else {
			// check against objects
			immutable float r = 10; /// unit detection radius 
			foreach(u; g.world.units)
				{
				if(u !is this) 
					{
					//if(u.myTeamIndex != myTeamIndex)  later
					if(pos.x + offset.x - r < u.pos.x && 
						pos.x + offset.x + r > u.pos.x &&
						pos.y + offset.y - r < u.pos.y &&
						pos.y + offset.y + r > u.pos.y)
						{
/+						if(isDebugging)
							{
							writefln("[%s].pos[%s] vs [%s].pos[%s]", u.toString, u.pos, this.toString, pos);
							writeln(" - true");
							}+/
						if(!isPlayerControlled)this.pos -= offset; // ??? not sure if best place for this. stutters for a player character
						return false;
						}else{
/+						if(isDebugging)
							{
							writefln("[%s].pos[%s] vs [%s].pos[%s]", u.toString, u.pos, this.toString, pos);
							writeln(" - false");
							}+/
						}
					}
			}
			// check against map
			if(isMapValid(ip3))
				{
				ushort tileType = g.world.map.bmpIndex[ip3.i][ip3.j];
				if(isHalfHeightTile(tileType))
					{
					// NOTE: We need non-tile coordinates here based on where we WANT TO MOVE
					if((pos.y + offset.y) % TILE_H > TILE_H/2)
						{
	//					if(isDebugging)writeln("isHalfHeightTile ", pos, " ",pos.y % TILE_H, " + ");
						pos += offset;
						return true;
						}else{
	//					if(isDebugging)writeln("isHalfHeightTile ", pos, " ",pos.y % TILE_H, " - ");
						return true;
						}
					}
				if(isPassableTile(tileType))
					{ // if normal passable
//					if(isDebugging)writeln("isPassableTile ", pos, " ", pos.y % TILE_H);
					pos += offset;
					return true;
					}
				if(isTreeWalker && isForestTile(tileType))
					{ // if treewalker is forestpassable, and in forest, go half speed (or whatever modifier)
//					if(isDebugging)writeln("isForestTile ", pos, " ", pos.y % TILE_H);
					pos.x += offset.x/2; //fixme. DEX based.
					pos.y += offset.y/2; //fixme. DEX based.
					return true;
					}else{
	//				if(isDebugging)writeln("!isForestTile ", pos, " ", pos.y % TILE_H);
					return false;
					}
				return false; // note, this fall-through ordering is important.
				}else{
				return false;
				}
			}
		assert(0);
		}

	void doWorldClipping()
		{
		if(pos.x < 0){pos.x = 0; vel.x = -vel.x; isFlipped=true;}
		if(pos.x >= (g.world.map.width)*TILE_W){pos.x = (g.world.map.width)*TILE_W-1; vel.x = -vel.x; isFlipped=true;}
		if(pos.y < 0){pos.y = 0; vel.y = -vel.y;}
		if(pos.y >= (g.world.map.height)*TILE_W){pos.y = (g.world.map.height)*TILE_H-1; vel.y = -vel.y;}
		}
	
	void setDirectionToVelocity(pair v) /// so looking direction follows AI velocity 
		{
		// we don't have diagonals made yet so lets just do left/right
		if(v.x < 0) direction = DIR.LEFT;
		if(v.x > 0) direction = DIR.RIGHT;
		}
	
	void setRandomDirection()
		{
		vel = apair(uniform!"[]"(0, 2*PI), WALK_SPEED*cstats.dex); // if we were stuck, then map editor freed us, lets start moving again.
		}
	
	void travel()
		{
		if(!attemptMove(vel))
			{
			// flip direction
//			vel = pair(-vel.x, -vel.y); // dont have negative opapply yet so can't do vel = -vel;
//			vel -= vel; // CONFIRM
			setRandomDirection();
			setDirectionToVelocity(vel);
			}else{
			}

		if(vel == 0)setRandomDirection();
		}
	
	void handleCooldowns()
		{
		primary.onTick();
		special.onTick();
		}
	
	override void onTick()
		{			
		if(mp < mpMax)mp += manaChargeRate;
		handlePotions();
		handleCooldowns();
		if(!isPlayerControlled && !freezeMovement)travel();
		doWorldClipping();
		}
		
	void onCollision(baseObject who)
		{
		}
	/+	
	void onHit(bullet b) //projectile based damage
		{
		// b.myOwner
		}
+/
	void onCrash(unit byWho) //for crashing into each other/objects
		{
		}

	void doAttackStructure(structure s)
		{
		s.onHit(this, weapon_damage);
		}

	void doAttack(unit u)
		{
		u.onAttack(this, weapon_damage);
		}
		
	void onAttack(unit from, float amount) /// I've been attacked!
		{
		cstats.hp -= amount;
		}
		
	void onHit(unit u, float damage)
		{
		cstats.hp -= damage;
		if(cstats.hp <= 0)
			{
			if(!isDebugging) //need to deal with "on death, notify viewport to find a new unit on team"
				{
				g.world.blood.add(pos.x, pos.y);
				g.world.blood.add(pos.x+5, pos.y);
				g.world.blood.add(pos.x-5, pos.y);
				g.world.blood.add(pos.x, pos.y+5);
				g.world.blood.add(pos.x, pos.y-5);

				isDead = true;
				}
			}
		}
	
	override void actionFire()
		{
		if(primary.isReadySet())
			{
			g.world.bullets ~= new bullet( this.pos, pair(apair( toAngle(direction), 10)), toAngle(direction), red, 100, 0, this, 0);
			}
		}

	override void actionUp()
		{
		if(!freezeMovement)
			{
			attemptMove(pair(0, -WALK_SPEED*cstats.dex));
			direction = DIR.UP;
			} 
		}
		
	override void actionDown()
		{
		if(!freezeMovement)
			{
			attemptMove(pair(0, WALK_SPEED*cstats.dex));
			direction = DIR.DOWN;
			}
		}
		
	override void actionLeft()
		{
		if(!freezeMovement)
			{
			attemptMove(pair(-WALK_SPEED*cstats.dex, 0));
			direction = DIR.LEFT;
			}
		}
		
	override void actionRight()
		{
		if(!freezeMovement)
			{
			attemptMove(pair(WALK_SPEED*cstats.dex, 0));
			direction = DIR.RIGHT;
			}
		}
	}

class baseObject /// does nothing but draws an object
	{
	ALLEGRO_BITMAP* bmp;	/// for non
	bool isDead = false;	/// Time to delete me?	
	pair pos; 				/// baseObjects are centered at X/Y (not top-left) so we can easily follow other baseObjects.
	pair vel; 				/// Velocities.
	float w=0, h=0;   		/// width, height 
	float angle=0;			/// pointing angle 
	bool isDebugging=false; /// Do we spam debug messages? (normally false and set yes for object you care about.)

	@disable this(); 
	this(pair _pos, pair _vel, BITMAP* _bmp)
		{
		pos = _pos;
		vel = _vel;
		bmp = _bmp;
//		writeln("I set x y", _x, " ", _y);
		}
		
	bool draw(viewport v)
		{
		drawCenterRotatedBitmap(bmp, vpair(pos), angle, 0);
		return true;
		}
	
	// INPUTS 
	// ------------------------------------------
	void actionUp(){}
	void actionDown(){}
	void actionLeft(){}
	void actionRight(){}
	void actionFire(){}
	void actionSpecial(){}
	void actionShifter(){}
	void actionFour(){} // four button controller. find better name when applicable{

	void onTick()
		{
		// THOU. SHALT. NOT. PUT. PHYSICS. IN BASE. baseObject.
		}
	}	
