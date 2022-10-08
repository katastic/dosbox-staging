/+
	script.d
	
	scripting routines for cinematics/textboxes

	---> FUNNY. every time you press skip, your character portrait shakes like he's angry. Further the more you do it.
		So instead of just skipping time, you can also make your guy look like he's losing his shit with impatience
		during conversations.

		- chatbox
		- move
		- attack
		- die
		- play animation like emotes
		- spawn
+/

import viewportsmod;
import objects;

class object2_t : controllee
	{
	override void actionUp(){}
	override void actionDown(){}
	override void actionLeft(){}
	override void actionRight(){}
	override void actionJump(){}
	override void actionAttack(){}
	override void actionUse(){}
	}

interface controllee
	{
	void actionUp();
	void actionDown();
	void actionLeft();
	void actionRight();
	void actionJump();
	void actionAttack();
	void actionUse();
	}

// each conversation is a set of dialogs that can be "skipped" forward and then the next plays.
class conversation
	{
	dialogInstance[] dialogs; 
	}

class dialogInstance
	{
//	BITMAP* avatar; // Portrait of speaker, just name the thing portrait?
	string name; // Name of speaker
	string[] lines;   // Do we support RICH TEXT? italics, bold, colors? /SPECIAL/ /TEXT/
	// for special names like bosses or [instructions] you should pay attention to.
	// Do we store a diary of previous conversations so people can look up important things?
	// or skip the middle man and just keep a list objectives
	
	bool isQuestion=false; // ends with question prompt
	bool isBooleanQuestion=false; // yes/no
	bool isChoiceQuestion=false; // three or more choices
	string[] choices;
	
	bool hasSound=false;
	int playSoundAtIndex; // Play sound at lines[x]
	int playSoundOffset; // Play sound at [y] letter of [x] (for delayed sounds on long lines)

	int lastLineGiven=0; 
		
	bool hasMoreLines()
		{
		if(lastLineGiven < lines.length)return true; else return false;
		}
		
	string nextLine()
		{
		if(lastLineGiven < lines.length)
			{
			lastLineGiven++;
			return lines[lastLineGiven-1];
			}else{
			return ""; // UGH. SENTINAL VALUES?
			}
		}
		
	// Do we also draw() from this class or is this just text data to be fed into modalbox
	// which can then choose to format it as it pleases?
	// HOWEVER, if that's the case, without geometry, how do we know how much text we can give it?
	}

class modalBox
	{
	float x, y;
	string[] lines;
	
	bool isPlayer;
	float angerValue=0; // bigger anger, higher starting velocity in random direction. If away from center, pointed mostly back at center.
	float anger_offset_x=0, anger_offset_y=0; // current offset from portrait center.
	float anger_velocity_x=0, anger_velocity_y=0; 
	
	void draw(viewport v) // public
		{
		}

	void onTick()
		{
		}	
	
	// how to do fast-forward, also holding button only finishes a dialog instance, it does not 
	// automatically continue past a button prompt.
		
	void stepForward() // if dialog is cut off, continue dialog. If i
		{
		}

	private void playDialogVowelSound() // ala Banjo and Kazooie, and others  
		{
		}

	private void drawBoxBackground(viewport v)
		{
		}
	}
	
class animation_t //npc animation
	{
		// nyi
	}

enum STATE{ NONE=0, DELAY, WAITING};
/// waiting - waiitng on user input (for decision or end of dialog)

class scriptHandler
	{
	STATE state;
	controllee control;
	float cooldown = 0;
	
	bool spawnModalBinaryBox(string text) /// Spawn modal yes-no box
		{
			// How do we tell the controls/controls handler that we're modal and we need all input context sent here?
			// we might be able to have a controls handler, with a pointer, that sends all key presses there.
			//
		bool answer = false; 
		return answer;
		}

	void onTick()
		{
		if(state == STATE.DELAY)
			{
			if(cooldown > 0)cooldown--; else doSomething();
			}
		}
	
	void doSomething()
		{
		}

	void delay(float milliseconds)
		{
		immutable float FPS = 60;
		cooldown = FPS*milliseconds*1000f;
		}

	void setNPCAnimation(animation_t anim)
		{
		}
		
	void getNPCAnimation(unit o)
		{
		}
	}
