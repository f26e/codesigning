usage="Usage example:
$(basename "$0") -s path -c certificate [-p path] [-b identifier]

where:
-s  is the path to the ipa file which you want to sign or re-sign
-c  is the signing certificate name or its SHA-1 hash from Keychain
-p  [Optional] path to mobile provisioning file
-b  [Optional] Bundle identifier"


while getopts s:c:p:b: option
do
    case "${option}"
    in
      s) SOURCEIPA=${OPTARG}
         ;;
      c) DEVELOPER=${OPTARG}
         ;;
      p) MOBILEPROV=${OPTARG}
         ;;
      b) BUNDLEID=${OPTARG}
         ;;
     \?) echo "invalid option: -$OPTARG" >&2
         echo "$usage" >&2
         exit 1
         ;;
      :) echo "missing argument for -$OPTARG" >&2
         echo "$usage" >&2
         exit 1
         ;;
    esac
done


echo "# Re-Signing STARTED ####"

OUTDIR=$(dirname "${SOURCEIPA}")
TMPDIR="$OUTDIR/tmp"
APPDIR="$TMPDIR/app"


mkdir -p "$APPDIR"
unzip -qo "$SOURCEIPA" -d "$APPDIR"

APPLICATION=$(ls "$APPDIR/Payload/")


# Remove previous code signature
echo "Remove previous code signature"
rm -rf "$APPDIR/Payload/$APPLICATION/_CodeSignature"

# Copy new distribution profile into the .app package
echo "Copy new distribution profile into the .app package"
cp "$MOBILEPROV" "$APPDIR/Payload/$APPLICATION/embedded.mobileprovision"


#if [ -z "${BUNDLEID}" ]; then
echo "Sign process using existing bundle identifier from payload"
#else
# Rename the app’s bundle identifier in the info.plist file
echo "Changing BundleID with : $BUNDLEID"
/usr/libexec/PlistBuddy -c "Set:CFBundleIdentifier $BUNDLEID" "$APPDIR/Payload/$APPLICATION/Info.plist"
#fi


echo "Get list of components and resign with certificate: $DEVELOPER"
find -d "$APPDIR" \( -name "*.app" -o -name "*.appex" -o -name "*.framework" -o -name "*.dylib" \) > "$TMPDIR/components.txt"

var=$((0))
while IFS='' read -r line || [[ -n "$line" ]]; do
	if [[ ! -z "${BUNDLEID}" ]] && [[ "$line" == *".appex"* ]]; then
	   echo "Changing .appex BundleID with : $BUNDLEID.extra$var"
	   /usr/libexec/PlistBuddy -c "Set:CFBundleIdentifier $BUNDLEID.extra$var" "$line/Info.plist"
	   var=$((var+1))
	fi

 echo "Clean up artifacts"
 xattr -rc "$APPDIR/Payload/$APPLICATION"

 echo "Codesign"
 /usr/bin/codesign --continue -f -s "$DEVELOPER" --entitlements "$TMPDIR/Entitlements.plist" "$line"

done < "$TMPDIR/components.txt"


echo "Creating the signed ipa"
cd "$APPDIR"
filename=$(basename "$APPLICATION")
filename="${filename%.*}-resigned.ipa"
zip -qr "../$filename" *
cd ..
mv "$filename" "$OUTDIR"


echo "Clear temporary files"
rm -rf "$APPDIR"
rm "$TMPDIR/components.txt"
rm "$TMPDIR/provisioning.plist"
rm "$TMPDIR/entitlements.plist"

echo "# Re-Signing FINISHED ####"
