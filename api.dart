import 'dart:convert';
import 'dart:io';
import 'package:mysql_dart/mysql_dart.dart';

Future<MySQLConnection> abrirConexao() async {
  final conexao = await MySQLConnection.createConnection(
  host: '127.0.0.1',
  port: 3306,
  userName: 'root',
  password: '',
  databaseName: 'oficinageral',
  secure: false,
);

  await conexao.connect();
  return conexao;
}

Future<void> responder(HttpResponse resposta, int status, Object dados) async {
  resposta.statusCode = status;
  resposta.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
  resposta.write(jsonEncode(dados));
  await resposta.close();
}

Future<Map<String, String>?> lerCarro(HttpRequest requisicao) async {
  final texto = await utf8.decoder.bind(requisicao).join();
  final dados = jsonDecode(texto);
  if (dados is! Map ||
      dados['marcaCarro'] is! String ||
      dados['placaCarro'] is! String ||
      dados['proprietarioCarro'] is! String) {
    return null;
  }
  final marca = (dados['marcaCarro'] as String).trim();
  final placa = (dados['placaCarro'] as String).trim();
  final proprietario = (dados['proprietarioCarro'] as String).trim();
  if (marca.isEmpty || placa.isEmpty || proprietario.isEmpty) return null;
  return {
    'marcaCarro': marca,
    'placaCarro': placa,
    'proprietarioCarro': proprietario,
  };
}

Future<void> atender(HttpRequest requisicao) async {
  final metodo = requisicao.method;
  final partes = requisicao.uri.pathSegments;
  MySQLConnection? conexao;

  try {
    if (partes.isEmpty || partes.first != 'carros' || partes.length > 2) {
      await responder(requisicao.response, 404, {'erro': 'Rota nao encontrada.'});
      return;
    }

    final colecao = partes.length == 1;
    final permitido = (colecao && (metodo == 'GET' || metodo == 'POST')) ||
        (!colecao && (metodo == 'PUT' || metodo == 'DELETE'));
    if (!permitido) {
      await responder(requisicao.response, 405, {'erro': 'Metodo nao permitido.'});
      return;
    }

    int? id;
    if (!colecao) {
      id = int.tryParse(partes[1]);
      if (id == null || id <= 0) {
        await responder(requisicao.response, 400, {'erro': 'ID invalido.'});
        return;
      }
    }

    Map<String, String>? carro;
    if (metodo == 'POST' || metodo == 'PUT') {
      carro = await lerCarro(requisicao);
      if (carro == null) {
        await responder(requisicao.response, 400, {
          'erro': 'Informe marcaCarro, placaCarro e proprietarioCarro.'
        });
        return;
      }
    }

    conexao = await abrirConexao();

    if (metodo == 'GET') {
      final resultado = await conexao.execute(
        'SELECT `idCarro`, `marcaCarro`, `placaCarro`, `proprietarioCarro` '
        'FROM `tabelaCadastroCarros` ORDER BY `idCarro`',
      );
      final carros = resultado.rows.map((linha) {
        final dados = linha.assoc();
        return {
          'idCarro': int.tryParse(dados['idCarro'] ?? '') ?? dados['idCarro'],
          'marcaCarro': dados['marcaCarro'],
          'placaCarro': dados['placaCarro'],
          'proprietarioCarro': dados['proprietarioCarro'],
        };
      }).toList();
      await responder(requisicao.response, 200, carros);
      return;
    }

    if (metodo == 'POST') {
      await conexao.execute(
        'INSERT INTO `tabelaCadastroCarros` '
        '(`marcaCarro`, `placaCarro`, `proprietarioCarro`) '
        'VALUES (:marca, :placa, :proprietario)',
        {
          'marca': carro!['marcaCarro'],
          'placa': carro['placaCarro'],
          'proprietario': carro['proprietarioCarro'],
        },
      );
      final resultadoId = await conexao.execute('SELECT LAST_INSERT_ID() AS id');
      final novoId = int.tryParse(resultadoId.rows.first.colByName('id') ?? '');
      await responder(requisicao.response, 201, {'idCarro': novoId, ...carro});
      return;
    }

    // Confere se o carro existe antes de alterar ou excluir.
    final existente = await conexao.execute(
      'SELECT `idCarro` FROM `tabelaCadastroCarros` WHERE `idCarro` = :id',
      {'id': id},
    );
    if (existente.rows.isEmpty) {
      await responder(requisicao.response, 404, {'erro': 'Carro nao encontrado.'});
      return;
    }

    if (metodo == 'PUT') {
      await conexao.execute(
        'UPDATE `tabelaCadastroCarros` SET '
        '`marcaCarro` = :marca, `placaCarro` = :placa, '
        '`proprietarioCarro` = :proprietario WHERE `idCarro` = :id',
        {
          'marca': carro!['marcaCarro'],
          'placa': carro['placaCarro'],
          'proprietario': carro['proprietarioCarro'],
          'id': id,
        },
      );
      await responder(requisicao.response, 200, {
        'mensagem': 'Carro atualizado.', 'idCarro': id, ...carro,
      });
      return;
    }

    if (metodo == 'DELETE') {
      await conexao.execute(
        'DELETE FROM `tabelaCadastroCarros` WHERE `idCarro` = :id',
        {'id': id},
      );
      await responder(requisicao.response, 200, {'mensagem': 'Carro excluido.'});
      return;
    }
  } on FormatException {
    await responder(requisicao.response, 400, {'erro': 'JSON invalido.'});
  } catch (erro) {
    stderr.writeln('Erro na API: $erro');
    await responder(requisicao.response, 500, {
      'erro': 'Erro interno no servidor ou no banco de dados.'
    });
  } finally {
    await conexao?.close();
  }
}

Future<void> main() async {
  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  print('API OficinaGeral em http://localhost:8080/carros');
  await for (final requisicao in servidor) {
    atender(requisicao);
  }
}
