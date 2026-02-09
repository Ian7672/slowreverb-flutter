import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

class NativeAudioBridge {
  NativeAudioBridge._()
      : _lib = Platform.isAndroid
            ? ffi.DynamicLibrary.open('libslowreverb_native.so')
            : null {
    final lib = _lib;
    if (Platform.isAndroid && lib != null) {
      _create = lib.lookupFunction<_CreateNative, _CreateFn>(
        'slowreverb_engine_create',
      );
      _dispose = lib.lookupFunction<_VoidHandleNative, _VoidHandleFn>(
        'slowreverb_engine_dispose',
      );
      _start = lib.lookupFunction<_StartNative, _StartFn>(
        'slowreverb_engine_start',
      );
      _stop = lib.lookupFunction<_VoidHandleNative, _VoidHandleFn>(
        'slowreverb_engine_stop',
      );
      _setTempo = lib.lookupFunction<_DoubleSetterNative, _DoubleSetter>(
        'slowreverb_engine_set_tempo',
      );
      _setPitch = lib.lookupFunction<_DoubleSetterNative, _DoubleSetter>(
        'slowreverb_engine_set_pitch',
      );
      _setMix = lib.lookupFunction<_DoubleSetterNative, _DoubleSetter>(
        'slowreverb_engine_set_mix',
      );
      _setReverb = lib.lookupFunction<_ReverbSetterNative, _ReverbSetter>(
        'slowreverb_engine_set_reverb',
      );
      _getPosition = lib.lookupFunction<_GetDoubleNative, _GetDouble>(
        'slowreverb_engine_get_position_ms',
      );
      _getDuration = lib.lookupFunction<_GetDoubleNative, _GetDouble>(
        'slowreverb_engine_get_duration_ms',
      );
    } else {
      _create = null;
      _dispose = null;
      _start = null;
      _stop = null;
      _setTempo = null;
      _setPitch = null;
      _setMix = null;
      _setReverb = null;
      _getPosition = null;
      _getDuration = null;
    }
  }

  static final NativeAudioBridge instance = NativeAudioBridge._();

  final ffi.DynamicLibrary? _lib;
  late final _CreateFn? _create;
  late final _VoidHandleFn? _dispose;
  late final _StartFn? _start;
  late final _VoidHandleFn? _stop;
  late final _DoubleSetter? _setTempo;
  late final _DoubleSetter? _setPitch;
  late final _DoubleSetter? _setMix;
  late final _ReverbSetter? _setReverb;
  late final _GetDouble? _getPosition;
  late final _GetDouble? _getDuration;

  bool get isAvailable =>
      _lib != null &&
      _create != null &&
      _dispose != null &&
      _start != null &&
      _stop != null &&
      _setTempo != null &&
      _setPitch != null &&
      _setMix != null &&
      _setReverb != null &&
      _getPosition != null &&
      _getDuration != null;

  int createHandle() {
    if (!isAvailable) return 0;
    return _create!();
  }

  void dispose(int handle) {
    if (!isAvailable || handle == 0) return;
    _dispose!(handle);
  }

  int start(int handle, String path) {
    if (!isAvailable || handle == 0) return -1;
    final ptr = path.toNativeUtf8();
    final result = _start!(handle, ptr.cast());
    calloc.free(ptr);
    return result;
  }

  void stop(int handle) {
    if (!isAvailable || handle == 0) return;
    _stop!(handle);
  }

  void setTempo(int handle, double tempo) {
    if (!isAvailable || handle == 0) return;
    _setTempo!(handle, tempo);
  }

  void setPitch(int handle, double semi) {
    if (!isAvailable || handle == 0) return;
    _setPitch!(handle, semi);
  }

  void setMix(int handle, double wet) {
    if (!isAvailable || handle == 0) return;
    _setMix!(handle, wet);
  }

  void setReverb(
    int handle, {
    required double decay,
    required double tone,
    required double room,
    required double echoMs,
  }) {
    if (!isAvailable || handle == 0) return;
    _setReverb!(handle, decay, tone, room, echoMs);
  }

  double positionMs(int handle) {
    if (!isAvailable || handle == 0) return 0;
    return _getPosition!(handle);
  }

  double durationMs(int handle) {
    if (!isAvailable || handle == 0) return 0;
    return _getDuration!(handle);
  }
}

typedef _CreateNative = ffi.IntPtr Function();
typedef _CreateFn = int Function();
typedef _VoidHandleNative = ffi.Void Function(ffi.IntPtr);
typedef _VoidHandleFn = void Function(int);
typedef _StartNative = ffi.Int32 Function(
    ffi.IntPtr, ffi.Pointer<ffi.Int8>);
typedef _StartFn = int Function(int, ffi.Pointer<ffi.Int8>);
typedef _DoubleSetterNative = ffi.Void Function(ffi.IntPtr, ffi.Double);
typedef _DoubleSetter = void Function(int, double);
typedef _ReverbSetterNative = ffi.Void Function(
    ffi.IntPtr, ffi.Double, ffi.Double, ffi.Double, ffi.Double);
typedef _ReverbSetter = void Function(
    int, double, double, double, double);
typedef _GetDoubleNative = ffi.Double Function(ffi.IntPtr);
typedef _GetDouble = double Function(int);
