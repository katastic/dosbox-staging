import allegro5.allegro;
import allegro5.allegro_primitives;
import allegro5.allegro_image;
import allegro5.allegro_font;
import allegro5.allegro_ttf;
import allegro5.allegro_color;

import std.stdio;

import viewportsmod;
import objects;
import g;
import helper;

/// they use ITEMS for the following but these will be structures:
/// 	teleporter, level exit

class key : consumableItem /// key for specific door (or other)
	{
	uint keyNumber; /// each key number can be used for multiple doors, and gets added to your team
	this(pair _pos)
		{
		super(_pos);
		}

	override bool use(ref unit by)
		{
		teams[0].keys ~= keyNumber;
		return true;
		}
	}

class money : consumableItem /// copper, silver, gold bars
	{
	int amount = 100;
	this(pair _pos)
		{
		super(_pos);
		}

	override bool use(ref unit by)
		{
		if(!teams[by.myTeamIndex].isAI) /// don't give ENEMY AI teams money!
			{
			teams[by.myTeamIndex].money += amount;
			return true;
			}else{
			return false;
			}
		}
	}

class invulnerabilityPotion : consumableItem
	{
	int amount = 1000;
		
	this(pair _pos)
		{
		super(_pos);
		}

	override bool use(ref unit by)
		{
		by.invulnerabilityCooldown = amount;
		return true;
		}
	}

class flightPotion : consumableItem
	{
	int amount = 1000;

	this(pair _pos)
		{
		super(_pos);
		}

	override bool use(ref unit by)
		{
		by.flyingCooldown = amount;
		return true;
		}
	}

class healthPotion : consumableItem		/// small medium large meats also health potion
	{	/// threw in mana potion because it's almots identical
	int healAmount=30;
	bool isManaPotion=false;
	
	this(pair _pos)
		{
		super(_pos);
		}

	override bool use(ref unit by)
		{
		if(!isManaPotion)
			{
			by.cstats.hp += healAmount;
			clampHigh(by.cstats.hp, by.cstats.hpMax);
			}else{
			by.cstats.mp += healAmount; // healamount=mana here
			clampHigh(by.cstats.mp, by.cstats.mpMax);			
			}
		return true;
		}
	}

class consumableItem : item
	{
	this(pair _pos)
		{
		super(_pos);
		}

	bool use(ref unit by)
		{
		return true; //returns false for invalid pickup attempts.
		}

	override void onPickup(ref unit by)
		{
		if(by.myTeamIndex != 0) // neutral cannot pickup items, also AI teams? (should AI pickup food/potions? But not money!)
			//  && !teams[by.myTeamIndex].isAI
			use(by); 
		}

	}

class item : baseObject
	{
	bool isInside = false; //or isHidden? Not always the same though...
	int team;
	
	this(pair _pos)
		{	
		writeln("ITEM EXISTS BTW at ", _pos.x, " ", _pos.y);
		super(pair(_pos), pair(0,0),g.bmp.potion);
		}
		
	void onPickup(ref unit by)
		{
		}
		
	override bool draw(viewport v)
		{
		if(!isInside)
			{
			super.draw(v);
			return true;
			}
		return false;
		}
		
	override void onTick()
		{
		if(!isInside)
			{
			pos.x += vel.x;
			pos.y += vel.y;
			vel.x *= .99; 
			vel.y *= .99; 
			}
		}
	}
