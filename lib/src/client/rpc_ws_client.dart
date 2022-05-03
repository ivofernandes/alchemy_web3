import 'dart:async';
import 'dart:io';

import 'package:alchemy_web3/alchemy.dart';
import 'package:console_mixin/console_mixin.dart';
import 'package:dio/dio.dart';
import 'package:either_dart/either.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:web_socket_channel/io.dart';

import '../model/rpc/rpc_error_data.model.dart';

enum WsStatus {
  uninitialized,
  connecting,
  running,
  stopped,
}

class RpcWsClient with ConsoleMixin implements Client {
  // PROPERTIES
  String url;
  bool verbose;

  // CONSTRUCTOR
  RpcWsClient({
    this.url = '',
    this.verbose = false,
  });

  // GETTERS

  // VARIABLES
  Client? wsClient;
  WsStatus wsStatus = WsStatus.uninitialized;
  bool? lastRestarted;
  var timeOutDuration = Duration(seconds: 5);

  // FUNCTIONS
  void init({
    required String url,
    Duration timeOutDuration = const Duration(seconds: 5),
    bool verbose = false,
  }) {
    this.url = url;
    this.verbose = verbose;
    this.timeOutDuration = timeOutDuration;

    start();
  }

  Future<Either<RPCErrorData, dynamic>> request({
    required String method,
    required List<dynamic> params,
  }) async {
    if (url.isEmpty) throw 'Client URL is empty';
    if (wsStatus != WsStatus.running) await restart();
    if (verbose) console.verbose('Requesting... $url -> $method\n$params');

    // RESTART IF NECESSARY
    if (isClosed) {
      await restart();

      if (isClosed) {
        return Left(RPCErrorData(
          code: 0,
          message: 'No Internet Connection',
        ));
      }
    }

    // SEND REQUEST
    try {
      final response = await sendRequest(method, params);
      if (verbose) console.info('Response: $response');

      if (response == null) {
        return Left(RPCErrorData(
          code: 200,
          message: 'Null Response',
        ));
      }

      return Right(response ?? '');
    } on DioError catch (e) {
      if (e.response == null) {
        return Left(
          RPCErrorData(
            code: 0,
            message: 'Local Error: ${e.type}: ${e.message}',
          ),
        );
      }

      return Left(RPCErrorData.fromJson(e.response!.data));
    } catch (e) {
      // different error
      return Left(RPCErrorData(
        code: 0,
        message: 'Unknown Error: $e',
      ));
    }
  }

  Future<void> start() async {
    if (!isClosed) await stop();

    wsStatus = WsStatus.connecting;
    console.info('Socket Connecting...');

    try {
      final socket = await WebSocket.connect(url).timeout(timeOutDuration);
      wsStatus = WsStatus.running;
      console.info('Socket Connected');

      wsClient = Client(IOWebSocketChannel(socket).cast<String>());
      wsClient!.listen().then((_) => restart);
    } catch (e) {
      console.warning('$e');
    }
  }

  Future<void> restart() async {
    console.info('Socket Restarting...');
    await start();
    console.info('Socket Restarted');
  }

  Future<void> stop() async {
    if (wsStatus != WsStatus.running || wsClient == null || isClosed) return;
    console.info('Socket Stopping...');
    await wsClient!.close();
    wsStatus = WsStatus.stopped;
    console.info('Socket Stopped');
  }

  @override
  Future sendRequest(String method, [parameters]) {
    return wsClient!.sendRequest(method, parameters).timeout(timeOutDuration);
  }

  @override
  bool get isClosed {
    return wsClient?.isClosed ?? false;
  }

  @override
  Future close() {
    throw UnimplementedError();
  }

  @override
  Future get done => throw UnimplementedError();

  @override
  Future listen() {
    throw UnimplementedError();
  }

  @override
  void sendNotification(String method, [parameters]) {}

  @override
  void withBatch(Function() callback) {}
}