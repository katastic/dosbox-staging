# find three newlines (or more) in code files indicating wasted space
# 	pcregrep - perl enhanced grep
# 		-M multiline
# 		-n write line number
echo

echo "Searching for FIXMEs"
echo "--------------------------------------------------------------------------"
if ! grep -inr "fixme" ./src/*.d ; then
echo -e "\e[32mNone found!\e[0m"
fi
echo

echo "Searching for TODOs"
echo "--------------------------------------------------------------------------"
if ! grep -inr "todo" ./src/*.d ; then
echo -e "\e[32mNone found!\e[0m"
fi
echo

echo "Searching for multiple consecutive newlines in source files."
echo "--------------------------------------------------------------------------"
if ! pcregrep -nM '\n[\t]*\n[\t]*\n' ./src/*.d ; then
echo -e "\e[32mNone found!\e[0m"
fi
echo

echo "Searching for closing curley brackets with extra space after them"
echo "--------------------------------------------------------------------------"
if ! pcregrep -nM '}\n\s\n.*}' ./src/*.d ; then
	echo -e "\e[32mNone found!\e[0m"
fi
echo
