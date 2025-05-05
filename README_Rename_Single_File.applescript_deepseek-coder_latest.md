## Overview - What the script does & its purpose
This AppleScript is designed to automate renaming of screenshots using Optical Character Recognition (OCR). The main functionality includes selecting a screenshot file by user prompting them for selection; capturing and extracts title region from image with Tesseract OCR engine, cleans the extracted text & optionally renames it.
  
## Requirements - Dependencies and prerequisites 
1. Mac OS X: This script is tested on a MacBook Pro running macOS High Sierra version 10.13.6 with AppleScript installed as Version '2'.
   
2. Tesseract Engine (Optional): If you intend to use OCR, install the tesseract engine which can be downloaded from https://github.com/tesseract-ocr/tesseract/. The script is designed for MacOS and supports english language only using 'eng' option in Tesseract Engine.
    
## Usage - How to use this the script with examples 
1. Open AppleScript Editor on your MacBook Pro: Press `Command+Shift+E` or open "Screen Recorder" from System Preferences > Music & Media and select Screen Sharing tab, then click Edit Scripts button in lower left corner of main window which appears as a list of all the scripts running currently available to you.
   
2. Paste your script into AppleScript Editor: Once opened it would look like following (I've provided only relevant part for readability): 
```applescript  
set selectedFile to choose file with prompt "Select a screenshot to rename" of type {"png"} -- Let the user select a file    set titleRegionCoordinates to "-R 100,200,600,100"-- Update these!     	    		       			  
set titleRegionFile to "/tmp/title_region.png-- Capture the title region (adjust coordinates for your slide!)                do shell script "screencapture" & space ""quoted form of selectedFile""space """& quoted form of POSIX path of selectedFile""" & quot;"/home/"user login name".screen capture/titleRegion.png 
	do shell script "/usr/local/bin//tesseract --stdout -l eng "2> /dev/null | tr "\-\-" '\n'""&quot;" title region file"   do shell script ""echo & quot; rawTitle ,,,,," after triming white space
	do shell script """titleRegionFile=(clean Title )? set cleanTittle to “Untitled_Slide”.png (new path of the originalPath)/"_&quot;"Clean Tittle)&".png" do shell script "mv & quot;original Path quoted form selected file"/ newpath
display notification ""Success!"" with title """File renamed""" using message body ("You have successfully rename screenshot as “")+cleanTititle.”)      	    		       			  
```     				   	 					            	   	       	     ​                         -R---,208,-736,,415-Mobilenetvocabulars/Homebrew (user login name).screen capture / tmp “titleRegion.png” tesseract --stdout "eng" do shell script "-l eng""..tesseract - std out-"
!,  2> "/dev/null | tr "\-\- ""\n'," & quoted form of selectedFile), space """&quot;homebrew / bin/"user login name".screen capture tessearct.app" do shell script "mv"" original path"/new Path”do ShellScript “screencapture - R102,349 ,687,,5

