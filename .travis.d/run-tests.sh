#!/bin/bash

SWIFT_VERSION="`swift --version | head -1 | sed 's/^.*[Vv]ersion[\t ]*\([.[:digit:]]*\).*$/\1/g'`"
declare -a SWIFT_VERSION_LIST="(${SWIFT_VERSION//./ })"
SWIFT_MAJOR=${SWIFT_VERSION_LIST[0]}
SWIFT_MINOR=${SWIFT_VERSION_LIST[1]}
SWIFT_SUBMINOR_OPT=${SWIFT_VERSION_LIST[2]}
SWIFT_SUBMINOR=${SWIFT_SUBMINOR_OPT}
if [[ "x${SWIFT_SUBMINOR}" = "x" ]]; then SWIFT_SUBMINOR=0; fi

if [[ "$TRAVIS_OS_NAME" == "osx" ]]; then 
  # Gives “Swift Language Version” (SWIFT_VERSION) is required to be configured correctly for targets which use Swift. Use the [Edit > Convert > To Current Swift Syntax…] menu to choose a Swift version or use the Build Settings editor to configure the build setting directly.
  # w/ Xcode 8.3. We set the lang-version in the Base.xcconfig, presumably
  # Xcode 8.3 can't do this right ...

  if [[ ${SWIFT_MAJOR} -ge 4 ]]; then
    xcodebuild -scheme ZeeQL -sdk macosx test
  else
    echo "Not running tests on ${SWIFT_VERSION} yet ..."
  fi
else
  # Swift 3.1.1 just crashes being building the tests. Yay.
  # Swift 4 works fine.
  # Swift 4.1 fails the Codable tests.
  if [[ ${SWIFT_MAJOR} -ge 4 ]]; then
    if [[ ${SWIFT_MINOR} -gt 0 ]]; then
      echo "Not running tests on ${SWIFT_VERSION} yet ..."
    else
      swift test
    fi
  fi
fi
