using Toybox.BluetoothLowEnergy as Ble;

class ebikeData {
    var deviceName = null;
	var batteryValue = -1;		// batter % to display
	var modeValue = -1;			// assist mode to display
	var gearValue = -1;			// gear number to display
	var lastMACArray = null;	// byte array of MAC address of bike
	var lastLock = false;		// user setting for lock to MAC address (or not)
	var showList = [1, 0, 0];	// 3 user settings for which values to show
	var errorReport = "";
	
		// 2 service ids are advertised (by EW-EN100)
	var advertisedServiceUuid1 = Ble.stringToUuid("000018ff-5348-494d-414e-4f5f424c4500");	
	// we don't use this service (no idea what the data is)
	// lightblue phone app says the following service uuid is being advertised
	// but CIQ doesn't list it in the returned scan results, only the one above
	//var advertisedServiceUuid2 = Ble.stringToUuid("000018ef-5348-494d-414e-4f5f424c4500");	// this service we also use to get notifications for mode
	
	var batteryServiceUuid        = Ble.stringToUuid("0000180f-0000-1000-8000-00805f9b34fb");
	var batteryCharacteristicUuid = Ble.stringToUuid("00002a19-0000-1000-8000-00805f9b34fb");
	
	var modeServiceUuid        = Ble.stringToUuid("000018ef-5348-494d-414e-4f5f424c4500");		// also used in advertising
	var modeCharacteristicUuid = Ble.stringToUuid("00002ac1-5348-494d-414e-4f5f424c4500");
	
	var MACServiceUuid        = Ble.stringToUuid("000018fe-1212-efde-1523-785feabcd123");
	var MACCharacteristicUuid = Ble.stringToUuid("00002ae3-1212-efde-1523-785feabcd123");
	
    // set up the ble profiles we will use (CIQ allows up to 3 luckily ...) 
    function bleInitProfiles() {
        var avail = Ble.getAvailableConnectionCount();
		// System.println("ebike:bleInitProfiles avail:" + avail );
		
		// read - battery	
		var profile1 = { 
			:uuid => batteryServiceUuid,
			:characteristics => [ {
					:uuid => batteryCharacteristicUuid 
					} ]
		};
		
		// notifications - mode, gear
		// is speed, distance, range, cadence anywhere in the data?
		// get 3 notifications continuously:
		// 1 = 02 XX 00 00 00 00 CB 28 00 00 (XX=02 is mode)
		// 2 = 03 B6 5A 36 00 B6 5A 36 00 CC 00 AC 02 2F 00 47 00 60 00
		// 3 = 00 00 00 FF FF YY 0B 80 80 80 0C F0 10 FF FF 0A 00 (YY=03 is gear if remember correctly)
		// Mode is 00=off 01=eco 02=trail 03=boost 04=walk 
		var profile2 = {
			:uuid => modeServiceUuid,
			:characteristics => [ {
					:uuid => modeCharacteristicUuid,
					:descriptors => [ Ble.cccdUuid() ]	// for requesting notifications set to [1,0]?
				} ]
		};
		
		// light blue displays MAC address as: C3 FC 37 79 B7 C2
		// which happens to match this!:
		// 000018fe-1212-efde-1523-785feabcd123
		// 00002ae3-1212-efde-1523-785feabcd123
		// C2 b7 79 37 fc c3
		// read - mac address
		var profile3 = {
			:uuid => MACServiceUuid,
			:characteristics => [ {
					:uuid => MACCharacteristicUuid
				} ]
		};

		try
		{
    		Ble.registerProfile(profile1);
    		Ble.registerProfile(profile2);
    		Ble.registerProfile(profile3);
			//System.println("ebike:bleInitProfiles done" );
		}
		catch (e)
		{
		    //System.println("catch = " + e.getErrorMessage());
		    ebike.errorReport = "ErrBleInit";
		}
    }
	
}