import std.stdio;

int main()
	{
	bool[320] data;
	
	for(int i = 0; i < 320; i++)
		{
		//int x = (i%4)*80 + i/4; this is 4 into 16. the wrong direction!
		//he's moving up by EIGHTY not by FOUR?!		
		
		// 0 -> 0
		// 1 -> 80
		// 2 -> 160
		// 3 -> 240
		// 4 -> 1
		// 5 -> 81
		// 6 -> 161
		// 7 -> 241
		// 8 -> 2
		
		int x = (i*80 + i/(320/80))%320;
		//int x = (i*20 + i/(320/20))%320;
		if(i < 16)writeln(i, " = ", x);
		data[x] = true;
		}
/+
	write 155 0 at 5 5 addr[1620]
  write 155 0 at 25 5 addr[1700]
  write 152 0 at 45 5 addr[1780]
  write 152 0 at 65 5 addr[1860]
  write 152 0 at 5 6 addr[1940]
  write 152 0 at 25 6 addr[2020]
  write 153 0 at 45 6 addr[2100]
  write 153 0 at 65 6 addr[2180]
  write 153 0 at 5 7 addr[2260]
  write 153 0 at 25 7 addr[2340]
  write 155 0 at 45 7 addr[2420]
  write 155 0 at 65 7 addr[2500]
+/
				
		writeln();
	bool hasFailed=false;
	for(int i = 0; i <320; i++)
		{
		if(data[i] == false)
			{
			if(hasFailed == false)
				{
				hasFailed = true;
				writeln("FAIL on data:");
				}
			write(i, " ");
			}
		}
		
	writeln();
	return 0;	
	}
