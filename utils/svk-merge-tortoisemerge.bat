@echo off
copy %2 %2.yours
copy %4 %4.base
copy %6 %6.theirs
TortoiseMerge.exe /yourname:%1 /yours:%2.yours /basename:%3 /base:%4.base /theirname:%5 /theirs:%6.theirs /merged:%7 
