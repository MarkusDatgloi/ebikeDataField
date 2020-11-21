This project is a simple data field for Garmin watches, built using Garmin Connect IQ (CIQ).

This project was derived from Mark.Ai's project at https://github.com/markdotai/emtb which is released 
in the Garmin app store here: https://apps.garmin.com/en-US/apps/461743f9-b350-486f-bd87-613c7b0bab90.

It allows your watch to connect to a a Shimano STEPS e-bike using Bluetooth Low Energy (BLE) 
and displays information (like battery percentage, assist mode, gear number).
Because Mark published his project (code) on GitHub and the datafield did not work on my VivoActive 4 I started to investigate his work. 
Searching for bugs I also started to change his code and had a peek in jim_m_58's code. The result is the code you see here.

THE BUG: there is no bug in Mark's code. The bug is somewhere in Garmin's CIQ software on some watches.
An CIQ app using BluetoothLowEnergie (BLE) can register up to 3 Bluetooth Profile Definitions.
On the VivoActive 4, and Venu watches, the registration fails for every 2nd and 3rd profile.
The result is that the app connects over BLE with the ebike but data is not exchanged and that is mistaken by users as an app failure.
This app will display an error message "ErrPrf_1" or "ErrPrf_2" where 1 and 2 are the failed number of registreations.
See the bug report and status at: https://forums.garmin.com/developer/connect-iq/i/bug-reports/vivoactive-4-bledelegate-onprofileregister-returns-status-value-2-on-every-2nd-and-3rd-registerprofile

This app is currently not released in the Garmin app store.

When you start developing for Garmin Connect IQ then don't forget to read this page:
https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq .
