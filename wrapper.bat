@echo off
mkdir mpv
mkdir mpv\7z
mkdir mpv\7z\lang
:: windows is stupid
move 7z\* mpv\7z
move 7z\lang\* mpv\7z\lang
move updater.bat mpv\
move updater.ps1 mpv\
cd mpv
updater.bat
