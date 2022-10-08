import g;
import viewportsmod;
import objects;
import helper;
import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;
import allegro5.allegro_color;

class gui_t
	{
	float x=0, y=0;
	unit myUnit;
	int flicker_cooldown = 20;
	
	this(ref unit u)
		{
		myUnit = u;
		}
		
	void onTick()
		{
		if(flicker_cooldown)flicker_cooldown--;
		}
		
	void setFlicker()
		{
		flicker_cooldown = 20;
		}
		
	void drawBackground(viewport v)
		{
		COLOR c = COLOR(.3, .3, .3, .9);
		float w = 200;
		float h = 40;
		al_draw_filled_rounded_rectangle(x, y, x + w-1, y + h-1, 5, 5, c); 
		}
	/+
	void drawSword(viewport v)
		{
		assert(g.sword_bmp != null);
		float x2 = x + v.x - g.sword_bmp.w/2 + 16 + 8;
		float y2 = y + v.y - g.sword_bmp.h/2 + 16 + 4;
		if(!u.hasSword)
			{
			
			ALLEGRO_COLOR c = ALLEGRO_COLOR(1.0, 0.5, 0.5, 1.0);
			if(p.stamina < 50) c = ALLEGRO_COLOR(1, 0, 0, 1); 
				
			if(flicker_cooldown)
				al_draw_scaled_bitmap(g.sword_bmp,
				   0, 0, g.sword_bmp.w, g.sword_bmp.h,
				   x2 - 10, y2 - 10, 
				   g.sword_bmp.w + 20, g.sword_bmp.h + 20, 
				   0);

			al_draw_tinted_bitmap(g.sword_bmp,
				c,
				x2, y2, 
				0);			

			}else{

			ALLEGRO_COLOR c = ALLEGRO_COLOR(1, 1, 1, 1);
			if(p.stamina < 50) c = ALLEGRO_COLOR(1, 0, 0, 1); 

			al_draw_tinted_bitmap(g.sword_bmp,
				c,
				x2, y2, 
				0);			
			}
		}+/

	void drawStamina(viewport v)
		{
		float w = 100;
		float wp = myUnit.mp / 100 * w; /// bar width percent * # pixels wide
		float h = 10;
		float x2 = x + 5;
		float y2 = y + 40;
		al_draw_rectangle(x2, y2, x2 + w-1, y2 + h-1, ALLEGRO_COLOR(1, 1, 0, 1), 2); 
		al_draw_filled_rectangle(x2, y2, x2 + wp-1, y2 + h-1, ALLEGRO_COLOR(1, 1, 0, 1)); 
		}

	void draw(viewport v)
		{
		drawBackground(v);
	//	drawSword(v);
		drawStamina(v);
		}

	//onTick() {}
	}
