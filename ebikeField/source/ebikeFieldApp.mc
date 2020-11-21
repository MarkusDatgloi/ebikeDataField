using Toybox.Application;
using Application.Properties as AppProps;
using Application.Storage as AppStorage;
using Toybox.BluetoothLowEnergy as Ble;

class ebikeFieldApp extends Application.AppBase {

    private var view;
    private var ebike;
    private var bleHandler;
    private var propsManager;
 
    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    // Return the initial view of your application here
    function getInitialView() {
		ebike = new ebikeData();
		
		propsManager = new ebikePropsManager(ebike);
        propsManager.getUserSettings();
        
		bleHandler = new ebikeBleDelegate(ebike, propsManager);
		Ble.setDelegate(bleHandler);
		ebike.bleInitProfiles();
		
		view = new ebikeFieldView(ebike, bleHandler, propsManager);
        return [ view ];
    }
    
    
    function onSettingsChanged() {
		propsManager.getUserSettings();
		// do some stuff in case the user has changed the MAC address or the lock flag
		if (bleHandler != null) {
			// if lastLock or lastMAC get changed dynamically while the field is running then should check if current bike connection is ok
			if (ebike.lastLock && ebike.lastMACArray != null && bleHandler.connectedMACArray != null &&
			   !bleHandler.sameMACArray(ebike.lastMACArray, bleHandler.connectedMACArray)) {
				bleHandler.bleDisconnect();
			}
			// And lets clear the scanned list, as if a device was scanned and excluded previously, maybe now it shouldn't be
			bleHandler.deleteScannedList();
		}
		view.onSettingsChanged();
	}

}