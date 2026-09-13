package com.example.billalert

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth draws the phone's fingerprint prompt as a fragment, so the
// activity has to be a FragmentActivity. With a plain FlutterActivity the
// plugin refuses every prompt as "uiUnavailable" — the button would appear
// to do nothing on a real phone while every test still passed.
class MainActivity : FlutterFragmentActivity()
