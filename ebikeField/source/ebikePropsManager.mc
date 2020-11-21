using Toybox.Application;
using Application.Properties as AppProps;
using Application.Storage as AppStorage;

class ebikePropsManager {

    private var ebike;

    function initialize(theEbike) {
        ebike = theEbike;
    }

	// Remember the current MAC address byte array, and also convert it to a string and store in the user settings 
	function saveLastMACAddress(newMACArray) {
		if (newMACArray!=null) {
			try {
		    	var s = StringUtil.convertEncodedString(newMACArray, {:fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY, :toRepresentation => StringUtil.REPRESENTATION_STRING_HEX});
		    	AppProps.setValue("LastMAC", s.toUpper());
			} catch (e) {
			    //System.println("catch = " + e.getErrorMessage());
		    	ebike.lastMACArray = null;     // Added
		    	ebike.errorReport= "ErrSvMACprops";
			}
		}
	}

	// Safely read a number value from user settings
	function propertiesGetNumber(p){
		var v = AppProps.getValue(p);
		if ((v == null) || (v instanceof Boolean)){
			v = 0;
		} else if (!(v instanceof Number)) {
			v = v.toNumber();
			if (v == null) {
				v = 0;
			}
		}
		return v;
	}

	// Safely read a string value from user settings
	function propertiesGetString(p) {	
		var v = AppProps.getValue(p);
		if (v == null) {
			v = "";
		} else if (!(v instanceof String)) {
			v = v.toString();
		}
		return v;
	}

	// Safely read a boolean value from user settings
	function propertiesGetBoolean(p){
		var v = AppProps.getValue(p);
		if ((v == null) || !(v instanceof Boolean)){
			v = false;
		}
		return v;
	}
	
	// read the user settings and store locally
	function getUserSettings() {
		//System.println("getUserSettings");
    	ebike.showList[0] = propertiesGetNumber("Item1");
    	ebike.showList[1] = propertiesGetNumber("Item2");
    	ebike.showList[2] = propertiesGetNumber("Item3");
//		System.println("  showList "+ebike.showList[0]+" "+ebike.showList[1]+" "+ebike.showList[2]);
		ebike.lastLock = propertiesGetBoolean("LastLock");
		
		// convert the MAC address string to a byte array
		// (if the string is an invalid format, e.g. contains the letter Z, then the byte array will be null)
		ebike.lastMACArray = null;
		var lastMAC = propertiesGetString("LastMAC");
		try {
			if (lastMAC.length() == 12) {  // was > 0 should be == 6; 6 bytes or 12 digits
	    		ebike.lastMACArray = StringUtil.convertEncodedString(lastMAC, {:fromRepresentation => StringUtil.REPRESENTATION_STRING_HEX, :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY});
	    	}
		} catch (e) {
			 //System.println("catch = " + e.getErrorMessage());
			ebike.lastMACArray = null;     // Just to be safe.
			ebike.errorReport = "ErrGetMACprop";
		}
	}

}