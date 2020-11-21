using Toybox.Application;
using Toybox.BluetoothLowEnergy as Ble;

// This is the BLE delegate class
// I've just added all my BLE related stuff to here too

class ebikeBleDelegate extends Ble.BleDelegate
{
	enum {
		STATE_INIT,			// starting up
		STATE_CONNECTING,	// scanning, choosing & connecting to a bike
		STATE_CONNECTED,			// reading data from our chosen bike
		STATE_DISCONNECTED,	// we've disconnected (so will need to scan etc again)
	}
	
	private var ebike;
    private var propsManager;

	var state = STATE_INIT;
	var connectedMACArray = null;	// MAC address byte array of bike we are (successfully) connected to 
	var currentScanning = false;	// scanning turned on?	
	var wantScanning = false;		// do we want it on?
	
	var wantReadBattery = false;
	var waitingRead = false;
	
	var wantNotifyMode = false;			// want notifications on?
	var waitingWrite = false;			// waiting for the write action to complete (which turns on or off the notifications)
	var writingNotifyMode = false;		// the on/off state we are currently in the process of writing
	var currentNotifyMode = false;		// the current on/off state (that we know from completed writes) 
	
	var readMACScanResult = null;			// this is the scan result that we are currently reading the MAC address of (to determine if it is the correct bike)
	var readMACCounter = 0;					// number of times we have started reading MAC for the current readMACScanResult
	const readMACCounterMaxAllowed = 5;		// number of times we have started reading MAC for the current readMACScanResult
		
	var scannedList = [];				// array of scan results that have been tested and deemed not worthy of connecting to
    const maxScannedListSize = 10;		// choose a max size just in case

	var profilesRegistered = 0;

	// scanResult.getRawData() returns this:
	// [3, 25, 128, 4, 2, 1, 5, 17, 6, 0, 69, 76, 66, 95, 79, 78, 65, 77, 73, 72, 83, 255, 24, 0, 0, 5, 255, 74, 4, 1, 0]
	// Raw advertising data format: https://www.silabs.com/community/wireless/bluetooth/knowledge-base.entry.html/2017/02/10/bluetooth_advertisin-hGsf
	// And the data types: https://www.bluetooth.com/specifications/assigned-numbers/generic-access-profile/
	//
	// So decoding gives:
	// 3, 25, 128, 4, (25=appearance) 0x8004
	// 2, 1, 5, (1=flags)
	// 17, 6, 0, 69, 76, 66, 95, 79, 78, 65, 77, 73, 72, 83, 255, 24, 0, 0, (6=Incomplete List of 128-bit Service Class UUIDs)
	//     (This in hex is 00 45 4c 42 5f 4f 4e 41 4d 49 48 53 ff 18 00 00, which matches 000018ff-5348-494d-414e-4f5f424c4500)
	// 5, 255, 74, 4, 1, 0 (255=Manufacturer Specific Data) (74 04 == Shimano BLE company id, which in decimal is 1098)
	//
	// Note that scanResult.getManufacturerSpecificData(1098) returns [1, 0]

    //==============================================
    // All functions called from embtView

	// in the process of scanning & choosing a bike?
	function isConnecting() {
		//System.println("isConnecting " + (state == STATE_CONNECTING || state == STATE_INIT));
		return (state == STATE_CONNECTING || state == STATE_INIT);
	}
	
	// successfully connected to our chosen bike?
	function isConnected() {
		//System.println("isConnected " + (state == STATE_CONNECTED));
		return (state == STATE_CONNECTED);
	}

	// call this when you want a battery reading
	function requestReadBattery() {
		//System.println("requestReadBattery");
		wantReadBattery = true;
	}
	
	// call this to turn on/off notifications for the mode/gear/other data blocks 
   	function requestNotifyMode(wantMode) {
		//System.println("requestNotifyMode " + wantMode);
   		wantNotifyMode = wantMode;
   	}
	
    // called from compute of emtbView
    function compute() {
		//System.println("compute");
		if (wantScanning != currentScanning) {
			Ble.setScanState(wantScanning ? Ble.SCAN_STATE_SCANNING : Ble.SCAN_STATE_OFF);	// Ble.SCAN_STATE_OFF, Ble.SCAN_STATE_SCANNING
		}

    	switch (state){
    	    case STATE_INIT:
    	    {
    	    	// initializing...
    	        break;
    	    }
    	    
			case STATE_CONNECTING:		// scanning & pairing until we connect to the bike
			{
				// waiting for onScanResults() to be called
				// and for it to decide to pair to something
				//
    			// Maybe if scanning takes too long, then cancel it and try again in "a while"?
    			// When View.onShow() is next called? (If user can switch between different pages ...)
				break;
			}
			
			case STATE_CONNECTED:	// connected, so now reading data as needed
			{
				// if there is no longer a paired device or it is not connected
				// then we have disconnected ...		
				var d = Ble.getPairedDevices().next();	// get first device (since we only connect to one at a time)
				if (d == null || !d.isConnected()) {
					bleDisconnect();
					state = STATE_DISCONNECTED;
				} else if (!waitingRead && !waitingWrite) {
					// do a read or write to the BLE device if we need to and nothing else is active
					if (wantReadBattery) {
						if (bleReadBattery()) {
							wantReadBattery = false;	// since we've started reading it
							waitingRead = true;
						} else {
				    		ebike.batteryValue = -1;		// read wouldn't start for some reason ...
						}
					} else if (wantNotifyMode != currentNotifyMode) {
						writingNotifyMode = wantNotifyMode;
	    				if (bleWriteNotifications(writingNotifyMode)) {
	    					waitingWrite = true;
	    				}
					}
				}
				break;
			}
			
			case STATE_DISCONNECTED:
			{	
			    if (profilesRegistered >= 3 ){			
    				startConnecting();		// start scanning to connect again
    			}
				break;
			}
    	}
    }
    
    //============================================================ 
    // All functions called by emtbView and this class   

    function bleDisconnect() {
		//System.println("bleDisconnect");
		var d = Ble.getPairedDevices().next();	// get first device (since we only connect to one at a time)
		if (d!=null) {
			Ble.unpairDevice(d);
		}
    }
    
	function sameMACArray(a, b)	{ // pass in 2 byte arrays
		// System.println("sameMACArray");
		if (a==null || b==null || a.size() != b.size()) {
			return false;
		}
		for (var i = 0; i < a.size(); i++) {
			if (a[i] != b[i]) {
				return false;
			}
		}
		return true;
	}
	
	function deleteScannedList() {
		//System.println("deleteScannedList");
    	scannedList = new[0];	// new zero length array
	}
	
	//==============================================
    // All functions called by this class ONLY
    
	// start the process of scanning for a bike to connect to
	private function startConnecting() {
		//System.println("startConnecting");
		ebike.deviceName = null;
		ebike.batteryValue = -1;
		ebike.modeValue = -1;
		ebike.gearValue = -1;
		state = STATE_CONNECTING;	
		connectedMACArray = null;
		wantScanning = true;
		readMACScanResult = null;
		deleteScannedList();
		writingNotifyMode = false;
		currentNotifyMode = false;
	}

	
	// Can only read the MAC address after BLE pairing to a bike (which we do while scanning)
	// this function will start a read
	private function startReadingMAC() {
		//System.println("startReadingMAC");
		if (readMACScanResult != null) {
			// System.println("startReadingMAC " + readMACScanResult + " " + Ble.getAvailableConnectionCount());
			// we keep a count of how many times we've attempted to read the MAC, because it really can fail sometimes
			// just set an upper limit so don't get stuck here forever
			if (readMACCounter < readMACCounterMaxAllowed) {
				if (bleReadMAC()) {
					// started reading the MAC address
					readMACCounter++;
				} else {
					readMACScanResult = null;
				}
			} else {
				readMACScanResult = null;
			}
		}
	}
	
	// Called after successfully reading of a MAC address from the currently paired bike (during scanning)
	private function completeReadMAC(readMACArray) {
		//System.println("completeReadMAC " + readMACArray);
		if (readMACScanResult != null) {
			// You are the device I'm looking for ...
			var foundDevice = (ebike.lastLock == false || 
			                   ebike.lastMACArray == null || 
			                   sameMACArray(ebike.lastMACArray, readMACArray) );

			if (foundDevice) {
				// store the MAC address into the user settings for next time
				ebike.lastMACArray = readMACArray;
				propsManager.saveLastMACAddress(readMACArray);
								
				// can stop scanning
				wantScanning = false;
				Ble.setScanState(Ble.SCAN_STATE_OFF);	// Ble.SCAN_STATE_OFF, Ble.SCAN_STATE_SCANNING				

				state = STATE_CONNECTED;
				connectedMACArray = readMACArray;	// remember the MAC address of whatever we've connected to
			} else {
				failedReadMACScan();	// or you're not the device I'm looking for ...
			}
		}
	}
	
	private function failedReadMACScan() {
		//System.println("failedReadMACScan");
		if (readMACScanResult != null) {
		    //System.println("failedReadMACScan "+ readMACScanResult);
			addToScannedList(readMACScanResult);	// remember this device has been scanned and not to try connecting to it again
			readMACScanResult = null;		// clear this so a new device can be tested

	    	// unpair & disconnect from this device so we can try connecting to another instead
			bleDisconnect();
		}
	}
	

    // tells the BLE device if we want mode/gear notifications on or off 
    private function bleWriteNotifications(wantOn) {
		//System.println("bleWriteNotifications " + wantOn);
       	var startedWrite = false;
    
    	// get first device (since we only connect to one at a time) and check it is connected
		var d = Ble.getPairedDevices().next();
		if (d!=null && d.isConnected()) {
            //System.println("bleWriteNotifications Name = " + d.getName());
			try {
				var ds = d.getService(ebike.modeServiceUuid);
				if (ds!=null) {
					var dsc = ds.getCharacteristic(ebike.modeCharacteristicUuid);
					if (dsc!=null) {
						var cccd = dsc.getDescriptor(Ble.cccdUuid());
						cccd.requestWrite([(wantOn ? 0x01 : 0x00), 0x00]b);
						startedWrite = true;
					}
				}
			} catch (e) {
			    //System.println("catch = " + e.getErrorMessage());
			    ebike.errorReport = "ErrWrtNot";		    
			}
		}
		return startedWrite;
	}
	
    private function bleReadBattery() {
		//System.println("bleReadBattery");
    	var startedRead = false;
    
    	// don't know if we can just keep calling requestRead() as often as we like without waiting for onCharacteristicRead() in between
    	// but it seems to work ...
    	// ... or maybe it doesn't, as always get a crash trying to call requestRead() after power off bike
    	// After adding code to wait for the read to finish before starting a new one, then the crash doesn't happen. 
    
    	// get first device (since we only connect to one at a time) and check it is connected
		var d = Ble.getPairedDevices().next();
		if (d!=null && d.isConnected()) {
            //System.println("bleReadBattery Name = " + d.getName());
			if ( ebike.deviceName == null ) {
				ebike.deviceName = d.getName();
			}
			try {
				var ds = d.getService(ebike.batteryServiceUuid);
				if (ds!=null) {
					var dsc = ds.getCharacteristic(ebike.batteryCharacteristicUuid);
					if (dsc!=null) {
						dsc.requestRead();	// had one exception from this when turned off bike, and now a symbol not found error 'Failed invoking <symbol>'
						startedRead = true;
					}
				}
			} catch (e) {
			    //System.println("catch = " + e.getErrorMessage());
			    ebike.errorReport = "ErrRdBat";		    
			}
		}
		return startedRead;
    }
    
    private function bleReadMAC() {
		//System.println("bleReadMAC");
    	var startedRead = false;
    
    	// get first device (since we only connect to one at a time) and check it is connected
		var d = Ble.getPairedDevices().next();
		if (d != null && d.isConnected()) {
	        // System.println("bleReadMAC name = " + d.getName()); --> null
			try {
				var ds = d.getService(ebike.MACServiceUuid);
				if (ds!=null) {
					var dsc = ds.getCharacteristic(ebike.MACCharacteristicUuid);
					if (dsc != null) {
						dsc.requestRead();
						startedRead = true;
					}
				}
			} catch (e) {
			    //System.println("catch = " + e.getErrorMessage());
			    ebike.errorReport = "ErrRdMAC";			    
			}
		}
		return startedRead;
    }
    
    private function iterContains(iter, obj) {
        var result = false;
        for (var uuid=iter.next(); uuid!=null; uuid=iter.next()) {
            if (uuid.equals(obj)) {
                result = true;
            }
        }
        //System.println("   iterContains " + result);
        return result;
    }

	private function addToScannedList(r) {
		//System.println("addToScannedList " + r);
		// if reached max size of scan list remove the first (oldest) one
		if (scannedList.size()>=maxScannedListSize) {
			scannedList = scannedList.slice(1, maxScannedListSize);  
		}
		// add new scan result to end of our scan list
		scannedList.add(r);
	}
	
    //==========================================================
	
    // BleDelegate 1
   	// initialize this delegate!   BleDelegate
    function initialize(theBike, thePropsManager) {
		//System.println("ble:initialize");
		ebike = theBike;
		propsManager = thePropsManager;
        BleDelegate.initialize();
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
   		startConnecting();
    }
    
    // BleDelegate 2
	// After enabling notifications or indications on a characteristic (by enabling the appropriate bit of the CCCD of the characteristic)
	// this function will be called after every change to the characteristic.
	function onCharacteristicChanged(characteristic, value) {
		//System.println("ble:onCharacteristicChanged "+ characteristic.getUuid().toString() + " " + value);
		if (characteristic.getUuid().equals(ebike.modeCharacteristicUuid)) {
			if (value!=null) {
				// value is a byte array
				if (value.size() == 10) {	// we want the one which is 10 bytes long (out of the 3 that Shimano seem to spam ...)
					ebike.modeValue = value[1].toNumber();	// and it is the 2nd byte of the array
				} else if (value.size() == 17) {
					ebike.gearValue = value[5].toNumber();
				}
			}
		}
	}
	
    // BleDelegate 3
	// After requesting a read operation on a characteristic using Characteristic.requestRead() this function will be called when the operation is completed.
	function onCharacteristicRead(characteristic, status, value) {
		//System.println("ble:onCharacteristicRead "+ characteristic.getUuid().toString() + " " + stateToString(status) + " " + value);
		if (characteristic.getUuid().equals(ebike.batteryCharacteristicUuid)) {
			if (value != null && value.size() > 0) {		// (had this return a zero length array once ...)
				ebike.batteryValue = value[0].toNumber();	// value is a byte array
			}
		} else if (characteristic.getUuid().equals(ebike.MACCharacteristicUuid)) {
			if (status == Ble.STATUS_SUCCESS) {
				//System.println("onCharacteristicRead "+ value);
				if (value != null && value.size() == 6) {    // ?? was > 0 or better == 6
					completeReadMAC(value.reverse());	     // reverse array order to properly match real MAC address as reported by phone
				} else {
					failedReadMACScan();
				}
			} else {
				startReadingMAC();	// try reading the MAC address again
			}
		}
		waitingRead = false;
	}
	
	// BleDelegate 4
	// Added for completeness and testing
	function onCharacteristicWrite(characteristic, status) {
	     //System.println("ble:onCharacteristicWrite "+ characteristic.getUuid().toString() + " " + stateToString(status));
	}

    // BleDelegate 5
	// After pairing a device this will be called after the connection is made.
	// (But seemingly not sometimes ... maybe if still connected from previous run of datafield?)
	function onConnectedStateChanged(device, connectionState) {
		//System.println("ble:onConnectedStateChanged " + device + " " + connectionStateToString(connectionState));
		if (connectionState == Ble.CONNECTION_STATE_CONNECTED) {
			startReadingMAC();
		}
	}

    // BleDelegate 6
    // Added for completeness and testing
    function onDescriptorRead(descriptor, status, value) {
		//System.println("ble:onDescriptorRead " + descriptor.getCharacteristic().getUuid().toString() + " " + stateToString(status) + " " + value);
    }

    // BleDelegate 7
	// After requesting a write operation on a descriptor using Descriptor.requestWrite() this function will be called when the operation is completed.
	function onDescriptorWrite(descriptor, status) {
		//System.println("ble:onDescriptorWrite " + descriptor.getCharacteristic().getUuid().toString() + " " + stateToString(status));
		var cd = descriptor.getCharacteristic();
		if (cd != null && cd.getUuid().equals(ebike.modeCharacteristicUuid)) {
			if (status==Ble.STATUS_SUCCESS) {
				currentNotifyMode = writingNotifyMode;
			}
		}
		waitingWrite = false;
	}

    // BleDelegate 8
    // Added for completeness and testing
    function onProfileRegister(uuid, status) {
        if (status == Ble.STATUS_SUCCESS ){
    		profilesRegistered++;
    	}
		// System.println("ble:onProfileRegister " + uuid.toString() + " " + stateToString(status));    
       	// ebike.displayString = "reg" + status;
	}
    
	// BleDelegate 9
	// If a scan is running this will be called when new ScanResults are received
    function onScanResults(scanResults) {
    	//printScanResults(scanResults);
    	//System.println("ble:onScanResults profiles:" + profilesRegistered);
    	if (profilesRegistered < 3){
    	    ebike.errorReport = "ErrPrf_" + (3 - profilesRegistered);
    	} else {
    		ebike.errorReport = "";
    	}
		if (!wantScanning) {
    	    //System.println(" -  onScanResults UNWANTED, return");
			return;
		}

		var newList = [];	// build array of new (unknown) devices to connect to
    	for (;;) {
    		var result = scanResults.next();
    		if (result == null) {
				// System.println(" 0 onScanResults: empty result, break");
    			break;
    		}
      		if (iterContains(result.getServiceUuids(), ebike.advertisedServiceUuid1)) {	// check the advertised uuids to see if right sort of device
      			// see if it is a device we haven't checked before
				var newResult = true;
				for (var i = 0; i < scannedList.size(); i++) {
					if ( result.isSameDevice(scannedList[i]) ) {
						scannedList[i] = result;		// update the scan info
						newResult = false;
         				//System.println("1 onScanResults " + newResult);
						break;
					}
				}
				if (newResult) {
					newList.add(result);
				}
				//System.println(" 2 onScanResults " + newResult);
			// } else {
				//System.println(" 3 onScanResults: NO advertisedServiceUuid1" );
			}
		}
		
		// System.println(" 4 onScanResults " + readMACScanResult + " " + newList.size());
		if (readMACScanResult == null && newList.size() > 0) {	// not already checking the MAC address of a device
			// find the new device which has the strongest signal
			var bestI = 0;
			var bestRssi = newList[0].getRssi();
	    	for (var i = 1; i < newList.size(); i++) {
	    		var rssi = newList[i].getRssi();
	    		if (rssi>bestRssi) {
	   				bestI = i;
	   				bestRssi = rssi;
	   			}
	   		}

			// lets try pairing to this device so we can check its MAC address
			readMACScanResult = newList[bestI];
			readMACCounter = 0;
  			var d = Ble.pairDevice(readMACScanResult);
  			if (d != null) {
			    //System.println(" 5 onScanResults +++ Paired device, name: " + d.getName() );
  				// it seems that sometimes after pairing onConnectedStateChanged() is not always called
  				// - checking isConnected() here immediately seems to avoid that case happening.
  				if (d.isConnected()) {
  					startReadingMAC();
  				}
  				
  			} else {
  				//System.println(" 6 onScanResults *** Pair device FAILED" + readMACScanResult);
				readMACScanResult = null;
  			}
//		} else {
//				System.println(" 7 onScanResults " + readMACScanResult + " " + newList.size());
		}
    }

    // BleDelegate 10
    function onScanStateChange(scanState, status) {
    	//System.println("ble:onScanStateChange " + scanStateToString(scanState) +" "+ stateToString(status));
    	currentScanning = (scanState == Ble.SCAN_STATE_SCANNING);
		readMACScanResult = null;		// make sure this is cleared whether starting or ending scanning
		deleteScannedList();
    }
        
    //======================================================
    // Added functions for testing
    
    private function stateToString(state){
        switch(state){
            case Ble.STATUS_NOT_ENOUGH_RESOURCES: { return "NOT_ENOUGH_RESOURCES"; }
            case Ble.STATUS_READ_FAIL: { return "READ_FAIL"; }
            case Ble.STATUS_SUCCESS: { return "SUCCESS"; }
            case Ble.STATUS_WRITE_FAIL: { return "WRITE_FAIL"; }
        }
        return "ERROR " + state;
    }
    
    private function scanStateToString(state){
        switch(state){
            case Ble.SCAN_STATE_OFF: { return "SCAN_STATE_OFF"; }
            case Ble.SCAN_STATE_SCANNING: { return "SCAN_STATE_SCANNING"; }
        }
        return "ERROR " + state;
    }
    
    private function connectionStateToString(state){
        switch(state){
            case Ble.CONNECTION_STATE_CONNECTED: { return "CONNECTED"; }
            case Ble.CONNECTION_STATE_DISCONNECTED: { return "DISCONNECTED"; }
            case Ble.CONNECTION_STATE_NOT_CONNECTED: { return "NOT_CONNECTED"; }
            case Ble.CONNECTION_STATE_NOT_INITIALIZED: { return "NOT_INITIALIZED"; }
        }
        return "ERROR " + state;
    }
    
//    private function printScanResults(scanResults){
//        System.println("onScanResults");
//        if (scanResults != null){
//	        var present = false;
//		    for( var result = scanResults.next(); (result != null) ; result = scanResults.next() ) {
//	            var uuids = result.getServiceUuids();
//	            if (uuids != null){
//		            System.println("   name=" + result.getDeviceName() + " " + result.getRssi());
//		            present = iterContains(result.getServiceUuids(), ebike.advertisedServiceUuid1);
//		            for ( var uuid = uuids.next(); uuid != null; uuid = uuids.next()){
//		            	System.println("   uuid " + uuid.toString() + " " + present);
//		            }
//	            }
//	    	}
//		}
//    }
    
}
