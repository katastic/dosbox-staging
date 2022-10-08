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

import std.stdio;
import std.math;
import std.random;

struct particle
	{
	pair pos;
	pair vel;
	int type=0;
	int lifetime=0;
	int maxLifetime=0;
	int rotation=0;
	bool isDead=false;

	//particle(x, y, vx, vy, 0, 5);
	/// spawn smoke without additional unit u
	this(pair _pos, pair _vel, int _type, int  _lifetime)
		{
		import std.math : cos, sin;
		pos.x = _pos.x;
		pos.y = _pos.y;
		vel.x = _vel.x + uniform!"[]"(-.1, .1);
		vel.y = _vel.y + uniform!"[]"(-.1, .1);
		type = _type;
		lifetime = _lifetime;
		maxLifetime = _lifetime;
		rotation = uniform!"[]"(0, 3);
		}
	
	/// spawn smoke with acceleration from unit u
	this(pair _pos, pair _vel, int _type, int  _lifetime, unit u)
		{// 	this(pair _pos, pair _vel, int _type, int  _lifetime)
		import std.math : cos, sin;
		float thrustAngle = u.angle;
		float thrustDistance = -30;
		float thrustVelocity = -3;
		
		pos.x = _pos.x + cos(thrustAngle)*thrustDistance;
		pos.y = _pos.y + sin(thrustAngle)*thrustDistance;
		vel.x = _vel.x + uniform!"[]"(-.1, .1) + cos(thrustAngle)*thrustVelocity;
		vel.y = _vel.y + uniform!"[]"(-.1, .1) + sin(thrustAngle)*thrustVelocity;
		type = _type;
		lifetime = _lifetime;
		maxLifetime = _lifetime;
		rotation = uniform!"[]"(0, 3);
		}
		
	bool draw(viewport v)
		{
		BITMAP *b = g.bmp.smoke;
		ALLEGRO_COLOR c = ALLEGRO_COLOR(1,1,1,cast(float)lifetime/cast(float)maxLifetime);
		float cx = pos.x + v.x - v.ox;
		float cy = pos.y + v.y - v.oy;
		float scaleX = (cast(float)lifetime/cast(float)maxLifetime) * b.w;
		float scaleY = (cast(float)lifetime/cast(float)maxLifetime) * b.h;

		if(cx > 0 && cx < SCREEN_W && cy > 0 && cy < SCREEN_H)
			{
			al_draw_tinted_scaled_bitmap(b, c,
				0, 0, 
				b.w, b.h,
				cx - b.w/2, cy - b.h/2, 
				scaleX, scaleY, 
				rotation);
			return true;
			}
		return false;
		}
	
	void onTick() // should we check for planets collision?
		{
		lifetime--;
		if(lifetime == 0)
			{
			isDead=true;
			}else{
			
			pos.x += vel.x;
			pos.y += vel.y;
			}
		}	
	}
	
