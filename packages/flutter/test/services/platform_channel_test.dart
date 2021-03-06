// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;

import '../flutter_test_alternative.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BasicMessageChannel', () {
    const MessageCodec<String> string = StringCodec();
    const BasicMessageChannel<String> channel = BasicMessageChannel<String>('ch', string);
    test('can send string message and get reply', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch',
        (ByteData message) async => string.encodeMessage(string.decodeMessage(message) + ' world'),
      );
      final String reply = await channel.send('hello');
      expect(reply, equals('hello world'));
    });
    test('can receive string message and send reply', () async {
      channel.setMessageHandler((String message) async => message + ' world');
      String reply;
      await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'ch',
        const StringCodec().encodeMessage('hello'),
        (ByteData replyBinary) {
          reply = string.decodeMessage(replyBinary);
        },
      );
      expect(reply, equals('hello world'));
    });
  });

  group('MethodChannel', () {
    const MessageCodec<dynamic> jsonMessage = JSONMessageCodec();
    const MethodCodec jsonMethod = JSONMethodCodec();
    const MethodChannel channel = MethodChannel('ch7', jsonMethod);
    const OptionalMethodChannel optionalMethodChannel = OptionalMethodChannel('ch8', jsonMethod);
    test('can invoke method and get result', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch7',
        (ByteData message) async {
          final Map<dynamic, dynamic> methodCall = jsonMessage.decodeMessage(message) as Map<dynamic, dynamic>;
          if (methodCall['method'] == 'sayHello') {
            return jsonMessage.encodeMessage(<dynamic>['${methodCall['args']} world']);
          } else {
            return jsonMessage.encodeMessage(<dynamic>['unknown', null, null]);
          }
        },
      );
      final String result = await channel.invokeMethod('sayHello', 'hello');
      expect(result, equals('hello world'));
    });

    test('can invoke list method and get result', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch7',
        (ByteData message) async {
          final Map<dynamic, dynamic> methodCall = jsonMessage.decodeMessage(message) as Map<dynamic, dynamic>;
          if (methodCall['method'] == 'sayHello') {
            return jsonMessage.encodeMessage(<dynamic>[<String>['${methodCall['args']}', 'world']]);
          } else {
            return jsonMessage.encodeMessage(<dynamic>['unknown', null, null]);
          }
        },
      );
      expect(channel.invokeMethod<List<String>>('sayHello', 'hello'), throwsA(isA<TypeError>()));
      expect(await channel.invokeListMethod<String>('sayHello', 'hello'), <String>['hello', 'world']);
    });

    test('can invoke list method and get null result', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch7',
        (ByteData message) async {
          final Map<dynamic, dynamic> methodCall = jsonMessage.decodeMessage(message) as Map<dynamic, dynamic>;
          if (methodCall['method'] == 'sayHello') {
            return jsonMessage.encodeMessage(<dynamic>[null]);
          } else {
            return jsonMessage.encodeMessage(<dynamic>['unknown', null, null]);
          }
        },
      );
      expect(await channel.invokeListMethod<String>('sayHello', 'hello'), null);
    });

    test('can invoke map method and get result', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch7',
        (ByteData message) async {
          final Map<dynamic, dynamic> methodCall = jsonMessage.decodeMessage(message) as Map<dynamic, dynamic>;
          if (methodCall['method'] == 'sayHello') {
            return jsonMessage.encodeMessage(<dynamic>[<String, String>{'${methodCall['args']}': 'world'}]);
          } else {
            return jsonMessage.encodeMessage(<dynamic>['unknown', null, null]);
          }
        },
      );
      expect(channel.invokeMethod<Map<String, String>>('sayHello', 'hello'), throwsA(isA<TypeError>()));
      expect(await channel.invokeMapMethod<String, String>('sayHello', 'hello'), <String, String>{'hello': 'world'});
    });

    test('can invoke map method and get null result', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch7',
        (ByteData message) async {
          final Map<dynamic, dynamic> methodCall = jsonMessage.decodeMessage(message) as Map<dynamic, dynamic>;
          if (methodCall['method'] == 'sayHello') {
            return jsonMessage.encodeMessage(<dynamic>[null]);
          } else {
            return jsonMessage.encodeMessage(<dynamic>['unknown', null, null]);
          }
        },
      );
      expect(await channel.invokeMapMethod<String, String>('sayHello', 'hello'), null);
    });

    test('can invoke method and get error', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch7',
        (ByteData message) async {
          return jsonMessage.encodeMessage(<dynamic>[
            'bad',
            'Something happened',
            <String, dynamic>{'a': 42, 'b': 3.14},
            'errorStacktrace',
          ]);
        },
      );
      try {
        await channel.invokeMethod<dynamic>('sayHello', 'hello');
        fail('Exception expected');
      } on PlatformException catch (e) {
        expect(e.code, equals('bad'));
        expect(e.message, equals('Something happened'));
        expect(e.details, equals(<String, dynamic>{'a': 42, 'b': 3.14}));
        expect(e.stacktrace, equals('errorStacktrace'));
      } catch (e) {
        fail('PlatformException expected');
      }
    });

    test('can invoke unimplemented method', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch7',
        (ByteData message) async => null,
      );
      try {
        await channel.invokeMethod<void>('sayHello', 'hello');
        fail('Exception expected');
      } on MissingPluginException catch (e) {
        expect(e.message, contains('sayHello'));
        expect(e.message, contains('ch7'));
      } catch (e) {
        fail('MissingPluginException expected');
      }
    });

    test('can invoke unimplemented method (optional)', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch8',
        (ByteData message) async => null,
      );
      final String result = await optionalMethodChannel.invokeMethod<String>('sayHello', 'hello');
      expect(result, isNull);
    });

    test('can handle method call with no registered plugin', () async {
      channel.setMethodCallHandler(null);
      final ByteData call = jsonMethod.encodeMethodCall(const MethodCall('sayHello', 'hello'));
      ByteData envelope;
      await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage('ch7', call, (ByteData result) {
        envelope = result;
      });
      expect(envelope, isNull);
    });

    test('can handle method call of unimplemented method', () async {
      channel.setMethodCallHandler((MethodCall call) async {
        throw MissingPluginException();
      });
      final ByteData call = jsonMethod.encodeMethodCall(const MethodCall('sayHello', 'hello'));
      ByteData envelope;
      await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage('ch7', call, (ByteData result) {
        envelope = result;
      });
      expect(envelope, isNull);
    });

    test('can handle method call with successful result', () async {
      channel.setMethodCallHandler((MethodCall call) async => '${call.arguments}, world');
      final ByteData call = jsonMethod.encodeMethodCall(const MethodCall('sayHello', 'hello'));
      ByteData envelope;
      await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage('ch7', call, (ByteData result) {
        envelope = result;
      });
      expect(jsonMethod.decodeEnvelope(envelope), equals('hello, world'));
    });

    test('can handle method call with expressive error result', () async {
      channel.setMethodCallHandler((MethodCall call) async {
        throw PlatformException(code: 'bad', message: 'sayHello failed', details: null);
      });
      final ByteData call = jsonMethod.encodeMethodCall(const MethodCall('sayHello', 'hello'));
      ByteData envelope;
      await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage('ch7', call, (ByteData result) {
        envelope = result;
      });
      try {
        jsonMethod.decodeEnvelope(envelope);
        fail('Exception expected');
      } on PlatformException catch (e) {
        expect(e.code, equals('bad'));
        expect(e.message, equals('sayHello failed'));
      } catch (e) {
        fail('PlatformException expected');
      }
    });

    test('can handle method call with other error result', () async {
      channel.setMethodCallHandler((MethodCall call) async {
        throw ArgumentError('bad');
      });
      final ByteData call = jsonMethod.encodeMethodCall(const MethodCall('sayHello', 'hello'));
      ByteData envelope;
      await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage('ch7', call, (ByteData result) {
        envelope = result;
      });
      try {
        jsonMethod.decodeEnvelope(envelope);
        fail('Exception expected');
      } on PlatformException catch (e) {
        expect(e.code, equals('error'));
        expect(e.message, equals('Invalid argument(s): bad'));
      } catch (e) {
        fail('PlatformException expected');
      }
    });

    test('can check the handler', () {
      Future<dynamic> handler(MethodCall call) => Future<dynamic>.value(null);

      const MethodChannel channel = MethodChannel('test_handler');
      expect(channel.checkMethodCallHandler(null), true);
      expect(channel.checkMethodCallHandler(handler), false);
      channel.setMethodCallHandler(handler);
      expect(channel.checkMethodCallHandler(handler), true);
    });

    test('can check the mock handler', () {
      Future<dynamic> handler(MethodCall call) => Future<dynamic>.value(null);

      const MethodChannel channel = MethodChannel('test_handler');
      expect(channel.checkMockMethodCallHandler(null), true);
      expect(channel.checkMockMethodCallHandler(handler), false);
      channel.setMockMethodCallHandler(handler);
      expect(channel.checkMockMethodCallHandler(handler), true);
    });
  });
  group('EventChannel', () {
    const MessageCodec<dynamic> jsonMessage = JSONMessageCodec();
    const MethodCodec jsonMethod = JSONMethodCodec();
    const EventChannel channel = EventChannel('ch', jsonMethod);
    void emitEvent(ByteData event) {
      ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'ch',
        event,
        (ByteData reply) { },
      );
    }
    test('can receive event stream', () async {
      bool canceled = false;
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch',
        (ByteData message) async {
          final Map<dynamic, dynamic> methodCall = jsonMessage.decodeMessage(message) as Map<dynamic, dynamic>;
          if (methodCall['method'] == 'listen') {
            final String argument = methodCall['args'] as String;
            emitEvent(jsonMethod.encodeSuccessEnvelope(argument + '1'));
            emitEvent(jsonMethod.encodeSuccessEnvelope(argument + '2'));
            emitEvent(null);
            return jsonMethod.encodeSuccessEnvelope(null);
          } else if (methodCall['method'] == 'cancel') {
            canceled = true;
            return jsonMethod.encodeSuccessEnvelope(null);
          } else {
            fail('Expected listen or cancel');
          }
        },
      );
      final List<dynamic> events = await channel.receiveBroadcastStream('hello').toList();
      expect(events, orderedEquals(<String>['hello1', 'hello2']));
      await Future<void>.delayed(Duration.zero);
      expect(canceled, isTrue);
    });
    test('can receive error event', () async {
      ServicesBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'ch',
        (ByteData message) async {
          final Map<dynamic, dynamic> methodCall = jsonMessage.decodeMessage(message) as Map<dynamic, dynamic>;
          if (methodCall['method'] == 'listen') {
            final String argument = methodCall['args'] as String;
            emitEvent(jsonMethod.encodeErrorEnvelope(code: '404', message: 'Not Found.', details: argument));
            return jsonMethod.encodeSuccessEnvelope(null);
          } else if (methodCall['method'] == 'cancel') {
            return jsonMethod.encodeSuccessEnvelope(null);
          } else {
            fail('Expected listen or cancel');
          }
        },
      );
      final List<dynamic> events = <dynamic>[];
      final List<dynamic> errors = <dynamic>[];
      channel.receiveBroadcastStream('hello').listen(events.add, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(errors, hasLength(1));
      expect(errors[0], isA<PlatformException>());
      final PlatformException error = errors[0] as PlatformException;
      expect(error.code, '404');
      expect(error.message, 'Not Found.');
      expect(error.details, 'hello');
    });
  });
}
