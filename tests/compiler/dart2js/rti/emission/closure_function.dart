// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.7

@pragma('dart2js:noInline')
test(o) => o is Function;

main() {
  test(

      /*strong.checks=[],instance*/
      /*omit.checks=[],instance*/
      () {});
  test(null);
}