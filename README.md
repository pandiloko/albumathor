# albumathor
Creates stupid albums for your phone pictures using EXIF metadata

albumathor takes a single file or a folder as input and creates albums using certain predefined patterns (namely same location, or close in time with other pictures). Also keeps track of the already processed files saving the blake2 checksum and other infos in a sqlite database. It doesn't matter if you change the origin or even the file name, albumathor will avoid duplicates and won't process the file twice. 

To convert GPS coordinates into human-readable locations, a third party reverse geolocation service is used. You'll need to create a user and obtain an API key at https://locationiq.com/ for this to work (it's free). 

This is still a work in progress. 
