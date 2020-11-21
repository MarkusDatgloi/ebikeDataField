using Toybox.Application;
using Toybox.WatchUi;
using Application.Properties as AppProps;

class baseView extends WatchUi.SimpleDataField
{
	var displayString = "";
	
	function initialize(){
		SimpleDataField.initialize();
	}
    
	function setLabelInInitialize(s){
		label = s;
	}

	// This method is called once per second and automatically provides Activity.Info to the DataField object for display or additional computation.
	function compute(info){
		return displayString;
	}
}
class ebikeFieldView extends baseView {

	private var ebike;
	private var bleHandler;		// the BLE delegate
    private var propsManager;
	
	private const secondsWaitBattery = 15;		// only read the battery value every 15 seconds
	private var secondsSinceReadBattery = secondsWaitBattery;

	private var modeNames = [
		"Off",
		"Eco",
		"Trail",
		"Boost",
		"Walk",
	];

	private var modeLetters = [
		"O",
		"E",
		"T",
		"B",
		"W",
	];

	private var connectCounter = 0;		// number of seconds spent scanning/connecting to a bike

    // Set the label of the data field here.
    function initialize(theBike, theBleDelegate, thePropsManager) {
		//System.println("initialize");
        baseView.initialize();
        ebike = theBike;
    	bleHandler = theBleDelegate;
		propsManager = thePropsManager;

        SimpleDataField.initialize();
        label = propsManager.propertiesGetString("Label");
    }

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
        // See Activity.Info in the documentation for available information.
    	// To test values use the "App settings editor"
    
    	// var showBattery = (showList[0]==1 || showList[1]==1 || showList[2]==2);   
    	var showBattery = (ebike.showList[0]==1 || ebike.showList[1]==1 || ebike.showList[2]==1);   
    	if (showBattery) {
	    	// only read battery value every 15 seconds once we have a value
	    	secondsSinceReadBattery++;
	    	if (ebike.batteryValue < 0 || secondsSinceReadBattery >= secondsWaitBattery){
	    		secondsSinceReadBattery = 0;
	    		bleHandler.requestReadBattery();
	    	}
		}
		    
    	var showMode = (ebike.showList[0]>=2 || ebike.showList[1]>=2 || ebike.showList[2]>=2);
    	bleHandler.requestNotifyMode(showMode);		// set whether we want mode or not (continuously)
		bleHandler.compute();
		
		// create the string to display to user
   		displayString = "";
		// could show status of scanning & pairing if we wanted
		if (bleHandler.isConnecting()) {
			connectCounter++;
			if (ebike.errorReport.length() > 3 && connectCounter > 5){
				displayString = ebike.errorReport;
			} else {
			    if (connectCounter > 20) {
					displayString = "power ON ?  " + connectCounter;
				} else {
					displayString = "Scan " + connectCounter;
				}
			}
		} else {
			connectCounter = 0;
			for (var i = 0; i < ebike.showList.size(); i++) {
				switch (ebike.showList[i]) {
					case 0:		// off
					{
						break;
					}

					case 1:		// battery
					{
	    				displayString += ((displayString.length()>0)?" ":"") + ((ebike.batteryValue>=0) ? ebike.batteryValue : "---") + "%";
						break;
					}

					case 2:		// mode name
					{
	    				displayString += ((displayString.length()>0)?" ":"") + ((ebike.modeValue>=0 && ebike.modeValue<modeNames.size()) ? modeNames[ebike.modeValue] : "----");
						break;
					}

					case 3:		// mode letter
					{
	    				displayString += ((displayString.length()>0)?" ":"") + ((ebike.modeValue>=0 && ebike.modeValue<modeLetters.size()) ? modeLetters[ebike.modeValue] : "-");
						break;
					}

					case 4:		// mode number
					{
	    				displayString += ((displayString.length()>0)?" ":"") + ((ebike.modeValue>=0) ? ebike.modeValue : "-");
						break;
					}

					case 5:		// gear
					{
    					displayString += ((displayString.length()>0)?" ":"") + ((ebike.gearValue>=0) ? ebike.gearValue : "-");
						break;
					}
				}  // end case
			}  // end for
		}
		if ( !ebike.errorReport.equals("") ){
			displayString = ebike.errorReport;
		} else {
			if (displayString.equals("") || displayString.find("-") != null){
			   if ( ebike.deviceName != null ) {
					displayString = ebike.deviceName;			   
			   } else {
					displayString = "Connected";
			   }
			} 
		}		
		// System.println(displayString);
		return baseView.compute(info);	// if a SimpleDataField then this will return the string/value to display
    }

	// called by app when settings change
	function onSettingsChanged() {
		//System.println("onSettingsChanged");
    	WatchUi.requestUpdate();   // update the view to reflect changes
	}
		
}