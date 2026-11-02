#!/bin/bash
set -euo pipefail

source_dir=$PWD
mkdir -p .build/deps
while read -r checksum url name; do
	curl --fail --location --retry 3 "$url" -o ".build/deps/$name"
	echo "$checksum  .build/deps/$name" | shasum -a 256 -c -
done <<'DEPENDENCIES'
d429e68102926f58bedd8e8b7105dcd169478cd6da1cef494a5f468482d1c8f5 https://github.com/holzschu/ios_system/releases/download/v3.0.5/ios_system.xcframework.zip ios_system.xcframework.zip
cacfe1789b197b727119f7e32f561eaf9acc27bf38cd19975b74fce107f868a6 https://github.com/holzschu/libssh2-apple/releases/download/v1.11.0/libssh2-dynamic.xcframework.zip libssh2.xcframework.zip
8a8de08e6ac9d1f6cb28e0c7e0c988ca2bb3a4de161a53b252a93d09d2af697a https://github.com/holzschu/openssl-apple/releases/download/v1.1.1w/openssl-dynamic.frameworks.zip openssl-frameworks.zip
51d46b912eb30399cbb5c36c8c8f15eb1a44adcfc9ee581304ac9d3739a84716 https://github.com/holzschu/ios_system/releases/download/v3.0.5/ios_error.h ios_error.h
DEPENDENCIES
unzip -oq .build/deps/ios_system.xcframework.zip -d .build/deps
unzip -oq .build/deps/libssh2.xcframework.zip -d .build/deps
mkdir -p .build/deps/openssl-frameworks
unzip -oq .build/deps/openssl-frameworks.zip -d .build/deps/openssl-frameworks

for platform in iphoneos iphonesimulator; do
	if [ "$platform" = iphoneos ]; then
		arch=arm64
		link_flags=(-target arm64-apple-ios14.0)
		dependency_slice=ios-arm64
		ssh_slice=ios-arm64_arm64e
		ssl_platform=iPhoneOS
	else
		arch="arm64;x86_64"
		link_flags=(-arch arm64 -arch x86_64 -mios-simulator-version-min=14.0)
		dependency_slice=ios-arm64_x86_64-simulator
		ssh_slice=$dependency_slice
		ssl_platform=iPhoneSimulator
	fi
	sdk=$(xcrun --sdk "$platform" --show-sdk-path)
	frameworks_dir="$source_dir/Frameworks_$platform"
	rm -rf "$frameworks_dir"
	mkdir -p "$frameworks_dir"
	cp -R .build/deps/ios_system.xcframework/"$dependency_slice"/ios_system.framework "$frameworks_dir/"
	cp -R .build/deps/libssh2.xcframework/"$ssh_slice"/libssh2.framework "$frameworks_dir/"
	cp -R .build/deps/openssl-frameworks/"$ssl_platform"/openssl.framework "$frameworks_dir/"

	cmake -S "$source_dir" -B "build-$platform" \
		-DBUILD_TESTS=OFF -DBUILD_CLI=OFF -DBUILD_EXAMPLES=ON -DBUILD_SHARED_LIBS=OFF \
		-DUSE_REGEX=builtin -DUSE_THREADS=OFF -DUSE_SSH=libssh2 -DUSE_HTTPS=SecureTransport \
		-DUSE_AUTH_NEGOTIATE=OFF -DUSE_COMPRESSION=zlib \
		-DPKG_CONFIG_EXECUTABLE=/usr/bin/false \
		-DLIBSSH2_LIBRARY="$frameworks_dir/libssh2.framework/libssh2" \
		-DLIBSSH2_INCLUDE_DIR="$frameworks_dir/libssh2.framework/Headers" \
		-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES="$arch" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_SYSROOT="$sdk" \
		-DCMAKE_C_COMPILER="$(xcrun --sdk "$platform" -f clang)" \
		-DCMAKE_C_FLAGS="-I$source_dir/.build/deps" \
		-DCMAKE_EXE_LINKER_FLAGS="-F$frameworks_dir -framework ios_system" \
		-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
	cmake --build "build-$platform" --target lg2 --parallel 3

	framework_dir=".build/Release-$platform/lg2.framework"
	rm -rf "$framework_dir"
	mkdir -p "$framework_dir"
	xcrun --sdk "$platform" clang "${link_flags[@]}" -dynamiclib -isysroot "$sdk" \
		-F"$frameworks_dir" build-"$platform"/examples/CMakeFiles/lg2.dir/*.c.o \
		build-"$platform"/libgit2.a -lpthread -framework CoreFoundation -framework Security \
		-framework libssh2 -framework openssl -framework ios_system -liconv -lz \
		-Wl,-install_name,@rpath/lg2.framework/lg2 -o "$framework_dir/lg2"
	if [ "$platform" = iphoneos ]; then
		cp basic_Info.plist "$framework_dir/Info.plist"
	else
		cp basic_Info_Simulator.plist "$framework_dir/Info.plist"
	fi
	plutil -replace CFBundleExecutable -string lg2 "$framework_dir/Info.plist"
	plutil -replace CFBundleName -string lg2 "$framework_dir/Info.plist"
	plutil -replace CFBundleIdentifier -string Nicolas-Holzschuch.lg2 "$framework_dir/Info.plist"
done

rm -rf .build/lg2.xcframework
xcodebuild -create-xcframework -framework .build/Release-iphoneos/lg2.framework \
	-framework .build/Release-iphonesimulator/lg2.framework -output .build/lg2.xcframework
rm -f .build/lg2.xcframework.zip
(cd .build && zip -rq lg2.xcframework.zip lg2.xcframework)
swift package compute-checksum .build/lg2.xcframework.zip
