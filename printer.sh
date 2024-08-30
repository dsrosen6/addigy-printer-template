#!/bin/bash

### Addigy-Specific Variables ###
## Uncomment lines as needed
pkg_file_name="Canon_PS_Installer.pkg" # TODO: Remove this when done testing

### Printer Variables ###
## REQUIRED VARIABLES - you must enter something for these! ##
current_version="1.3.0" # useful for deploying printer alterations over time. Should match the Custom Software version in Addigy.
display_name="Test Printer" # The printer name displayed to users, once deployed this should not change; changing the name will result in duplicate printers.
queue_name="Test_Printer" # Queue name of the printer - no spaces, use underscores! Best to use an underscored version of $display_name.
address="192.168.1.23" # Network address - such as an IP, hostname, or DNS-SD address.

## OPTIONAL VARIABLES ## - but, unless you're using a totally vanilla AirPrint setup, you'll probably use at least driver_ppd.
driver_ppd="/Library/Printers/PPDs/Contents/Resources/CNMCIRAC5750S2.ppd.gz" # If this is empty, the script will default to the AirPrint PPD.
custom_ppd="custom.ppd" # Custom PPD file. Use the name of the file you uploaded in Addigy.
protocol="lpd" # If empty, defaults to ipp. Option examples: dnssd, lpd, ipp, ipps, http, socket (use ipp for AirPrint)
location="Northway Church" # Physical location of the printer.

# Specific options for the printer.
# To find available options, manually add the printer to a Mac and run: lpoptions -p "$insert_cups_printer_name_here" -l
# To list installed CUPS printer queue names run: lpstat -p | /usr/bin/awk '{print $2}'
option_1=""
option_2=""
option_3=""

###############################################################
### DON'T MODIFY BELOW THIS LINE ##############################
###############################################################
### PREREQS ####################################
################################################
# Check to make sure all required variables aren't empty
if [[ -z "$current_version" ]] || [[ -z "$display_name" ]] || [[ -z "$queue_name" ]] || [[ -z "$address" ]]; then
    echo "One or more required variables are empty. Please fill in all required variables."
    exit 1
fi

################################################
### DRIVER FUNCTIONS ###########################
################################################
function set_protocol {
    # If protocol is not set, default to ipp
    if [[ -z "$protocol" ]]; then
        protocol="ipp"
    fi
}

function default_ppd_set {
    # Check if the default PPD file is set
    if [[ -n "$driver_ppd" ]]; then
        return 0
    else
        return 1
    fi
}

function default_ppd_exists {
    # Check if the default PPD file exists
    if [[ -e "$driver_ppd" ]]; then
        return 0
    else
        return 1
    fi
}

function use_airprint_ppd {
    # If driver_ppd is not set, default to AirPrint
    airprint_ppd="/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/PrintCore.framework/Resources/AirPrint.ppd"
    if ! default_ppd_set; then
        driver_ppd="$airprint_ppd"
        return 0
    else
        return 1
    fi
}

function custom_ppd_set {
    # Check if the custom PPD file is set
    if [[ -n "$custom_ppd" ]]; then
        return 0
    else
        return 1
    fi
}

function custom_ppd_exists {
    # Check if the custom PPD file exists
    if [[ -n "$custom_ppd" ]] && [[ -e "$custom_ppd" ]]; then
        return 0
    else
        return 1
    fi
}

function pkg_install_needed {
    if default_ppd_set && default_ppd_exists; then
        return 1
    else 
        return 0
    fi
}

function driver_pkg_set {
    # Check if the driver package file is set
    if [[ -n "$pkg_file_name" ]]; then
        return 0
    else
        return 1
    fi
}

function driver_pkg_exists {
    # Check if the driver package file exists
    if [[ -e "$pkg_file_name" ]]; then
        return 0
    else
        return 1
    fi
}

function install_driver_pkg {
    # Install the driver package
    /usr/sbin/installer -pkg "$pkg_file_name" -target /
}

################################################
### PRESENCE/VERSION/INSTALL FUNCTIONS #########
################################################
function printer_exists {
    if /usr/bin/lpstat -p "$queue_name" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

function converted_version {
    # Function to convert dot separated version numbers into an integer for comparison purposes.
    # Examples: "2.1.0" -> 2001000, "52.14.7" -> 52014007.
    echo "$@" | /usr/bin/awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }';
}

function get_installed_version {
    # Determine if the printer was previously installed.
    if [ -f "/private/etc/cups/deployment/receipts/${queue_name}.plist" ]; then
        # Get the script version number that was used to install the printer.
        installed_version=$(/usr/libexec/PlistBuddy -c "Print :version" "/private/etc/cups/deployment/receipts/${queue_name}.plist")
    else
        installed_version="0"
fi
}

function needs_install {
    # Compare the installed version with the current version.
    if [ "$(converted_version "$installed_version")" -ge "$(converted_version "$current_version")" ]; then
        return 1
    else
        return 0
    fi
}

function remove_printer {
    # Remove the printer queue.
    /usr/sbin/lpadmin -x "$queue_name"
}

function install_printer {
    # Install the printer queue.
    /usr/sbin/lpadmin -p "$queue_name" \
        -L "$location" \
        -D "$display_name" \
        -v "${protocol}"://"${address}" \
        -P "$driver_ppd" \
        -E \
        -o landscape \
        -o printer-is-shared=false \
        -o printer-error-policy=abort-job \
        -o "$option_1" \
        -o "$option_2" \
        -o "$option_3"

        if [ $? -eq 0 ]; then
            return 0
        else
            return 1
        fi
}

function update_receipt {
    # Create/update a receipt for the printer.
    /bin/mkdir -p /private/etc/cups/deployment/receipts
    /usr/libexec/PlistBuddy -c "Add :version string" "/private/etc/cups/deployment/receipts/${queue_name}.plist" 2> /dev/null || true
    /usr/libexec/PlistBuddy -c "Set :version $current_version" "/private/etc/cups/deployment/receipts/${queue_name}.plist"

    # Permission the directories properly.
    /usr/sbin/chown -R root:_lp /private/etc/cups/deployment
    /bin/chmod 755 /private/etc/cups/deployment
    /bin/chmod 755 /private/etc/cups/deployment/receipts

    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

################################################
### MAIN LOGIC #################################
################################################
# Check if a manufacturer PPD file is set - if not, use the AirPrint PPD
if use_airprint_ppd; then
    echo "No driver PPD file set - using AirPrint PPD"
else
    echo "Driver PPD file path set to $driver_ppd"
fi

# Set protocol to ipp if not manually
set_protocol && echo "Protocol set to $protocol"

# Check if driver package install is needed
if pkg_install_needed; then
    echo "Default driver is set, but not found. Package install needed."
    if driver_pkg_set && driver_pkg_exists; then
        echo "Driver package found - installing"
        install_driver_pkg && echo "Driver package installed successfully" || { echo "Driver package install failed"; exit 1; }
        if default_ppd_exists; then
            echo "Default driver file now present - continuing"
        else
            echo "Default driver file still not found - check to make sure the pkg contains the correct PPD"
            exit 1
        fi
    elif driver_pkg_set && ! driver_pkg_exists; then
        echo "Driver package set but file not found. Check your variables and try again."
        exit 1
    else
        echo "Driver package not set. Check your variables and try again."
        exit 1
    fi
else
    echo "Default driver file found - no package install needed"
fi

# Check if a custom PPD file is set - if so, use that instead of the default PPD
if custom_ppd_set; then
    echo "Custom PPD file path set to $custom_ppd"
    if custom_ppd_exists; then
        echo "Custom PPD found - setting that as the one to use"
        driver_ppd="$custom_ppd"
    else
        echo "No custom PPD found - check your variables and try again."
        exit 1
    fi
fi

# Check if the printer is already installed and if so, what version.
get_installed_version
if printer_exists; then
    echo "Printer queue already exists"
    if needs_install; then
        echo "The installed printer (${queue_name}) needs to be updated, will remove and reinstall."
        remove_printer
        install_printer && echo "Printer installed successfully" || { echo "Printer install failed"; exit 1; }
        echo "If you got a message about printer drivers being deprecated, you can ignore it."
        update_receipt && echo "Receipt updated successfully" || { echo "Receipt update failed"; exit 1; }
    else
        echo "The installed printer (${queue_name}) is already up-to-date, no need to reinstall."
    fi
else
    echo "Printer queue does not exist - installing"
    install_printer && echo "Printer installed successfully" || { echo "Printer install failed"; exit 1; }
    update_receipt && echo "Receipt updated successfully" || { echo "Receipt update failed"; exit 1; }
fi

exit 0