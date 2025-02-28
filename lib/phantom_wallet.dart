import 'dart:js_util' as js_util;
import 'firestore_functions.dart';
import 'dart:html' as html;

Future<String> connectPhantom() async {
  try{
    final result = await js_util.promiseToFuture<String>(
      js_util.callMethod(html.window, 'connectPhantom', []),
    );
    return result;
  }
  catch(e){
    errorLogger(e.toString(), 'connectPhantom() in phantom_wallet.dart');
    return 'error';
  }
}