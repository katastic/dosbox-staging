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
import guns;

import std.stdio;
import std.math;

/+
class planetTurret : turret
	{
	// >>USING RELATIVE COORDINATES<<
	this(float _x, float _y, baseObject _myOwner)
		{
		super(_x, _y, _myOwner, true); // special constructor
		myGun = new planetGun(this);
		}
	}

class attachedTurret : turret
	{
	float attachmentX;
	float attachmentY; // offset from 0,0 attachment point so we can rotate around it

	this(float _x, float _y, baseObject _myOwner)
		{
		super(_x, _y, _myOwner);
		isDebugging = true;
		}

	override bool draw(viewport v)
		{
		float dist = 50;
		float cangle = myOwner.angle;
		float cx = myOwner.x + v.x - v.ox + cos(cangle)*dist; // NOTE. we're currently NOT USING x,y
		float cy = myOwner.y + v.y - v.oy + sin(cangle)*dist; // because vector addition hard. apparently.
//			al_draw_centered_bitmap(bmp, cx, cy, 0);
		al_draw_center_rotated_bitmap(turretGun_bmp, cx, cy, angle, 0);
		return true;
		}
	
	override void onTick()
		{
//		writeln("I am a attachedTurret.ontick()");
		alignTurretandFire(); //TODO FIX ME. Change the coordinates
		}
	}

class turret : ship
	{
	// >>USING RELATIVE COORDINATES<<
	BITMAP* turretGun_bmp;
	baseObject myOwner;
	float TURRET_TRAVERSE_SPEED=degToRad(2);
	float TURRET_FIRE_DISTANCE=400f;
	
	this(float _x, float _y, baseObject _myOwner, bool dontSetupGun=true) // special case for planetTurret that will setup the gun
		{
		super(_x, _y, 0, 0);
		turretGun_bmp = g.turret_bmp;
		bmp = g.turret_base_bmp;
		myOwner = _myOwner;
		}

	/* how can we do this? Gun needs to know the ship!*/
	this(baseObject _myOwner) //, gun _myGun) 
		{
		float _x = _myOwner.x; 
		float _y = _myOwner.y; 
		super(_x, _y, 0, 0);

		myGun = new turretGun(this, yellow);
		turretGun_bmp = g.turret_bmp;
		bmp = g.turret_base_bmp;
		myOwner = _myOwner;	
		}
	
	this(float _x, float _y, baseObject _myOwner)
		{
		super(_x, _y, 0, 0);

		myGun = new turretGun(this, yellow);
		turretGun_bmp = g.turret_bmp;
		bmp = g.turret_base_bmp;
		myOwner = _myOwner;
		}

	override bool draw(viewport v)
		{
		al_draw_centered_bitmap(bmp, myOwner.x + x + v.x - v.ox, myOwner.y + y + v.y - v.oy, 0);
		al_draw_center_rotated_bitmap(turretGun_bmp, myOwner.x + x + v.x - v.ox, myOwner.y + y + v.y - v.oy, angle, 0);
		return true;
		}

	void alignTurretandFire()
		{
		pair absoluteP = pair(myOwner.x + x, myOwner.y + y); 
	
		// this simple section has turned into a nightmare of angles and tests not working
		
		// whenever we have "shoot the nearest enemy" we need to not shoot at our owner (or I guess our team, which counts as our owner)
		// but also not HITTING our owner.
	
		float destinationAngle = angleTo(g.world.units[0], absoluteP);
		float distance = distanceTo(g.world.units[0], absoluteP);
		//writeln(angle, " ", destinationAngle);
//		writeln(angle.radToDeg, " ", destinationAngle.radToDeg);

// --------------> read this thoroughly
// https://math.stackexchange.com/questions/110080/shortest-way-to-achieve-target-angle

// TODO: FIX THESE		
//		assert(angle == wrapRad(angle)); these are floats so we'd need to at least check a float /w range test
//		assert(destinationAngle == wrapRad(destinationAngle));
		angle = wrapRad(angle);
		destinationAngle = wrapRad(destinationAngle);
		
	//	auto t = angleDiff2(angle, destinationAngle + PI/2); //FIXME: Why is this off by 90 degrees?!?!? but not for all turrets!? what the hell is going on.
//		writeln(angle.radToDeg, " ", destinationAngle.radToDeg, " = ", t.radToDeg);
	//	if(t < 0)
		if(angle > destinationAngle)
			{
//			writeln("down");
			angle -= TURRET_TRAVERSE_SPEED;
		}else{
	//		writeln("up");
			angle += TURRET_TRAVERSE_SPEED;
			}
		 //grab target()
		myGun.onTick();
		vx = myOwner.vx; // note, these aren't "used" for our position, but are needed for spawning bullets
		vy = myOwner.vy; // that add with our velocity.
		
//		if(distance < TURRET_FIRE_DISTANCE)
		myGun.actionFireRelative(myOwner);
		}

	override void onTick()
		{
		alignTurretandFire();
		}
	}
+/
