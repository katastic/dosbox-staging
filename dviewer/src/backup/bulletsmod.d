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
import blood;

import std.random : uniform;
import std.math : cos, sin;
import std.stdio;

class elfBullet : bullet
	{
	bitmap* bmpOutlined;
	color outlineColor = color(1,1,1,1);
	this(pair _pos, pair _vel, float _angle, COLOR _c, int _type, int _lifetime, unit _myOwner, bool _isDebugging)
		{
		super(_pos, _vel, _angle, _c, _type, _lifetime, _myOwner, _isDebugging);
		isForestBullet = true;
		bmp = g.bmp.bulletRound;
		bmpOutlined = g.bmp.bulletRoundOutline;
		}

	override bool draw(viewport v)
		{
		if(isOnScreen(pos))
			{
			if(isOutlined)
				{
				drawCenterRotatedTintedBitmap(bmpOutlined, outlineColor, vpair(pos), angle + degToRad(90), 0); // not tinted, maybe later
				return true;
				}

			drawCenterRotatedTintedBitmap(bmp, c, vpair(pos), angle + degToRad(90), 0);

			return true;
			}
		return false;
		}
	}

class bullet : baseObject
	{
	bool isDebugging=false;
	float angle=0;
	int type; // 0 = normal bullet whatever
	int lifetime; // frames passed since firing
	bool isDead=false; // to trim
	bool isForestBullet=false;
	unit myOwner;
	COLOR c;
	bool isOutlined = false;
	
	this(pair _pos, pair _vel, float _angle, COLOR _c, int _type, int _lifetime, unit _myOwner, bool _isDebugging)
		{
		isDebugging = _isDebugging;
		c = _c;
		myOwner = _myOwner;
		pos.x = _pos.x;
		pos.y = _pos.y;
		vel.x = _vel.x;
		vel.y = _vel.y;
		type = _type;
		lifetime = _lifetime;
		angle = _angle;
		super(pair(this.pos), pair(this.vel), g.bmp.bullet);
		}
	
	void applyV(float applyAngle, float _vel)
		{
		vel.x += cos(applyAngle)*_vel;
		vel.y += sin(applyAngle)*_vel;
		}

	bool checkUnitCollision(unit u)
		{
//		writefln("[%f,%f] vs u.[%f,%f]", x, y, u.x, u.y);
		if(pos.x - 10 < u.pos.x)
		if(pos.x + 10 > u.pos.x)
		if(pos.y - 10 < u.pos.y)
		if(pos.y + 10 > u.pos.y)
			{
//		writeln("[bullet] Death by unit contact.");
			return true;
			}		
		return false;
		}
		
	void dieFrom(unit from)
		{
		isDead=true;
		vel.x = 0;
		vel.y = 0;
		g.world.particles ~= particle(pair(this.pos), pair(this.vel), 0, uniform!"[]"(3, 6));
		if(isDebugging) writefln("[debug] bullet at [%3.2f, %3.2f] died from [%s]", pos.x, pos.y, from);
		g.world.blood.add(pos.x, pos.y);
		}

	void die()
		{
		isDead=true;
		vel.x = 0;
		vel.y = 0;
		g.world.particles ~= particle(pair(this.pos), pair(this.vel), 0, uniform!"[]"(3, 6));
		if(isDebugging) writefln("[debug] bullet at [%3.2f, %3.2f] died from border or lifetime", pos.x, pos.y);
		}

	void dieFromWall()
		{
		isDead=true;
		vel.x = 0;
		vel.y = 0;
		g.world.particles ~= particle(pair(this.pos), pair(this.vel), 0, uniform!"[]"(3, 6));
		if(isDebugging) writefln("[debug] bullet at [%3.2f, %3.2f] died from wall", pos.x, pos.y);
		}

	bool attemptMove(pair offset) // similiar to units.attemptmove
		{
		ipair ip3 = ipair(this.pos, offset.x, offset.y); 
		if(isMapValid(ip3))
			{
			ushort index = g.world.map.bmpIndex[ip3.i][ip3.j];
			if(isForestBullet && isForestTile(index))
				{
				isOutlined = true;
				// we'll need to draw these objects twice. one for the outline, one for the object, otherwise we cannot tint the bullet separate from the outline.
				}else{
				isOutlined = false;
				}
			if(isShotPassableTile(index) || (isForestBullet && isForestTile(index)))
				{
				this.pos += offset;
				return true;
				}else{
				return false;
				}
			}else{
			writeln(this.pos, " ", offset);
			dieFromWall();
			return false;
			}
		}
	
	override void onTick()
		{
		lifetime--;
		if(lifetime == 0)
			{
			isDead=true;
			}else{
			 // UNIT SCAN
			foreach(u; g.world.units)
				{
				immutable float r = 16; // radius
				if(u !is myOwner)
				if(pos.x - r < u.pos.x)
				if(pos.y - r < u.pos.y)
				if(pos.x + r > u.pos.x)
				if(pos.y + r > u.pos.y)
					{
					float BULLET_DAMAGE = 5;
					u.onHit(myOwner, BULLET_DAMAGE);
					dieFrom(u);
					break;
					}
				// collision with units
				}
			// STRUCTURE SCAN
			foreach(u; g.world.structures)
				{
				immutable float r = 16; // radius
				if(u !is myOwner)
				if(pos.x - r < u.pos.x)
				if(pos.y - r < u.pos.y)
				if(pos.x + r > u.pos.x)
				if(pos.y + r > u.pos.y)
					{
					float BULLET_DAMAGE = 5;
					u.onHit(myOwner, BULLET_DAMAGE);
					dieFrom(u);
					break;
					}
				// collision with units
				}
				
			if(!attemptMove(vel))die(); // Map test and movement
			}
		
//		if(!isMapValid(ip3))dieFromWall();
//		if(pos.x < 0 || pos.y < 0 || pos.x > g.world.map.width*TILE_W || pos.y > g.world.map.height*TILE_H)die();
		}
	
	override bool draw(viewport v)
		{		
		if(isOnScreen(pos))
			{
			drawCenterRotatedTintedBitmap(bmp, c, vpair(pos), angle + degToRad(90), 0);
			return true;
			}
		return false;
		}
	}
