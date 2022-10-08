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
import bulletsmod;

import std.stdio;
import std.math;
import std.random;

/+
class laser : gun
	{
	this(ship newOwner)
		{
		super(newOwner, red);
		gunCooldownTime = 0; //instant fire
		damage = 1;
		} // not sure how we spawn laser beams. Could be as simple as projecting a line.
		
	override void fireProjectile()
		{
		// spawn laser projectile. (still on g.world.bullets?)
		// but it's a line.
		// maybe a 'laser bullet' structure that requires source position (player) and destination pos?
		}
	}

class minigun : gun
	{
	this(ship newOwner)
		{
		super(newOwner, red);
		gunCooldownTime = 2;
		spreadArc=5;
		roundsFired=1;
		speed=20;
		}
	}

class shotgun : gun
	{
	this(ship newOwner)
		{
		super(newOwner, blue);
		gunCooldownTime = 30;
		spreadArc=10;
		roundsFired=20;
		bulletColor = orange;
		}
	}

class turretGun : gun //slow firing, normal gun
	{
	this(ship newOwner, COLOR _c)
		{
		super(newOwner, _c);
		cooldown = uniform!"[]"(0,30);
		gunCooldownTime = 30;
		isAffectedByGravity = false;
		}
	}

class planetGun : turretGun // so bullets can leave, no gravity on them.
	{
	@disable this();
		
	this(ship newOwner)
		{
		super(newOwner, red);
		isAffectedByGravity = false; 
		}
	}
+/
class gun
	{
	bool isDebugging=false;
	float ammoLeft=100; // float in case we need to do some sort of "eats 1.5 units fluid per frame" logic
	float ammoRechargeRate=1; // This lets us "rate limit" spamming. Fire, out, wait for it to refill. [Can still fire before its full]
	float damage=5;
	int cooldown=5;
	int gunCooldownTime=5;
	int roundsFired=1;
	float speed=10;
	float spreadArc=0; // fixed spread arc degrees (degrees left and right. think 2x for total spread)
	float recoil; // increases with more shots more often
	float recoilCooldown; // nyi
	bool isShotgun=false; //spread. needed?
	unit myOwner;
	bool isAffectedByGravity=true;
	COLOR bulletColor;
	
	this(unit newOwner, COLOR _bulletColor)
		{
		bulletColor = _bulletColor;
		myOwner = newOwner;
		}
	
	void fireProjectile()
		{
		with(myOwner) //CAREFUL not to shadow variables here!
			{
			pair _vel = pair(vel.x + cos(angle + uniform!"[]"(-spreadArc, spreadArc).degToRad)*speed,
						 vel.y + sin(angle + uniform!"[]"(-spreadArc, spreadArc).degToRad)*speed);
			g.world.bullets ~= new bullet(pos, _vel, angle, bulletColor, 0, 100, myOwner, isDebugging);
			} 
		}
	
	void fireProjectileRelative(baseObject secondOwner)
		{
		with(myOwner) //CAREFUL not to shadow variables here!
			{
			pair _vel = pair(vel.x + cos(angle + uniform!"[]"(-spreadArc, spreadArc).degToRad)*speed,
					vel.y + sin(angle + uniform!"[]"(-spreadArc, spreadArc).degToRad)*speed);
			g.world.bullets ~= new bullet(pair(pos, secondOwner.pos.x, secondOwner.pos.y), _vel, angle, bulletColor, 0, 100, myOwner, isDebugging);
			}
		}
	
	void onTick()
		{
		if(cooldown > 0)
			{
			cooldown--;
		//	writeln(cooldown);
			}
		}
	
	void actionFireRelative(baseObject secondOwner)
		{
		if(cooldown == 0)
			{
			for(int i = 0; i < roundsFired; i++){//writeln("gun.fireRel()");
fireProjectileRelative(secondOwner);}
			cooldown = gunCooldownTime;
			}
		}

	void actionFire()
		{
		if(cooldown == 0)
			{
			for(int i = 0; i < roundsFired; i++){//writeln("gun.fire()");
fireProjectile();}
			cooldown = gunCooldownTime;
			}
		}
	}

