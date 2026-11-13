import 'dart:convert';
import 'dart:io';
import 'package:mysql1/mysql1.dart';

// Configuracao de conexao (equivalente a uma string de conexao).
// Altere os valores conforme seu MySQL local.
final configuracaoMySQL = ConnectionSettings(
  host: Platform.environment['DB_HOST'] ?? '127.0.0.1',
  port: int.tryParse(Platform.environment['DB_PORT'] ?? '') ?? 3306,
  user: Platform.environment['DB_USER'] ?? 'root',
  password: Platform.environment['DB_PASSWORD'] ?? '',
  db: Platform.environment['DB_NAME'] ?? 'OficinaGeral',
);

Future<void> responder(HttpResponse resposta, int status, Object dados) async {
  resposta.statusCode = status;
  resposta.headers.contentType = ContentType.json;
  resposta.write(jsonEncode(dados));
  await resposta.close();
}

Future<void> atender(HttpRequest requisicao) async {
  final metodo = requisicao.method;
  final caminho = requisicao.uri.path;
  MySqlConnection? conexao;

  try {
    // Cada requisicao abre uma conexao e a fecha no finally.
    // Simples para estudo; em producao, use pool e configuracao segura.
    if (caminho != '/carros' && !caminho.startsWith('/carros/')) {
      await responder(requisicao.response, 404, {'erro': 'Rota nao encontrada.'});
      return;
    }
    if (!(metodo == 'GET' && caminho == '/carros') &&
        !(metodo == 'POST' && caminho == '/carros') &&
        !(metodo == 'DELETE' && caminho.startsWith('/carros/')) &&
        !(metodo == 'PUT' && caminho.startsWith('/carros/'))) {
      await responder(requisicao.response, 405, {'erro': 'Metodo nao permitido.'});
      return;
    }

    if (metodo == 'POST') {
      final texto = await utf8.decoder.bind(requisicao).join();
      final dados = jsonDecode(texto);
      if (dados is! Map ||
          dados['marcaCarro'] is! String ||
          dados['placaCarro'] is! String ||
          dados['proprietarioCarro'] is! String ||
          (dados['marcaCarro'] as String).trim().isEmpty ||
          (dados['placaCarro'] as String).trim().isEmpty ||
          (dados['proprietarioCarro'] as String).trim().isEmpty) {
        await responder(requisicao.response, 400, {
          'erro': 'Informe marcaCarro, placaCarro e proprietarioCarro.'
        });
        return;
      }
      conexao = await MySqlConnection.connect(configuracaoMySQL);
      final marca = (dados['marcaCarro'] as String).trim();
      final placa = (dados['placaCarro'] as String).trim();
      final proprietario = (dados['proprietarioCarro'] as String).trim();
      final resultado = await conexao.query(
        'INSERT INTO `tabelaCadastroCarros` '
        '(`marcaCarro`, `placaCarro`, `proprietarioCarro`) VALUES (?, ?, ?)',
        [marca, placa, proprietario],
      );
      await responder(requisicao.response, 201, {
        'idCarro': resultado.insertId,
        'marcaCarro': marca,
        'placaCarro': placa,
        'proprietarioCarro': proprietario,
      });
      return;
    }

    if (metodo == 'GET') {
      conexao = await MySqlConnection.connect(configuracaoMySQL);
      final resultados = await conexao.query(
        'SELECT `idCarro`, `marcaCarro`, `placaCarro`, `proprietarioCarro` '
        'FROM `tabelaCadastroCarros` ORDER BY `idCarro`',
      );
      final carros = resultados.map((linha) => {
        'idCarro': linha['idCarro'],
        'marcaCarro': linha['marcaCarro'],
        'placaCarro': linha['placaCarro'],
        'proprietarioCarro': linha['proprietarioCarro'],
      }).toList();
      await responder(requisicao.response, 200, carros);
      return;
    }

    // PUT /carros/ID: atualiza todos os campos do carro informado.
    if (metodo == 'PUT') {
      final id = int.tryParse(caminho.substring('/carros/'.length));
      if (id == null || id <= 0) {
        await responder(requisicao.response, 400, {'erro': 'ID invalido.'});
        return;
      }

      final texto = await utf8.decoder.bind(requisicao).join();
      final dados = jsonDecode(texto);
      if (dados is! Map ||
          dados['marcaCarro'] is! String ||
          dados['placaCarro'] is! String ||
          dados['proprietarioCarro'] is! String ||
          (dados['marcaCarro'] as String).trim().isEmpty ||
          (dados['placaCarro'] as String).trim().isEmpty ||
          (dados['proprietarioCarro'] as String).trim().isEmpty) {
        await responder(requisicao.response, 400, {
          'erro': 'Informe marcaCarro, placaCarro e proprietarioCarro.'
        });
        return;
      }

      final marca = (dados['marcaCarro'] as String).trim();
      final placa = (dados['placaCarro'] as String).trim();
      final proprietario = (dados['proprietarioCarro'] as String).trim();
      conexao = await MySqlConnection.connect(configuracaoMySQL);
      final existente = await conexao.query(
        'SELECT `idCarro` FROM `tabelaCadastroCarros` WHERE `idCarro` = ?',
        [id],
      );
      if (existente.isEmpty) {
        await responder(requisicao.response, 404, {'erro': 'Carro nao encontrado.'});
        return;
      }
      await conexao.query(
        'UPDATE `tabelaCadastroCarros` SET '
        '`marcaCarro` = ?, `placaCarro` = ?, `proprietarioCarro` = ? '
        'WHERE `idCarro` = ?',
        [marca, placa, proprietario, id],
      );
      await responder(requisicao.response, 200, {
        'mensagem': 'Carro atualizado.',
        'idCarro': id,
        'marcaCarro': marca,
        'placaCarro': placa,
        'proprietarioCarro': proprietario,
      });
      return;
    }

    if (metodo == 'DELETE') {
      final id = int.tryParse(caminho.substring('/carros/'.length));
      if (id == null || id <= 0) {
        await responder(requisicao.response, 400, {'erro': 'ID invalido.'});
        return;
      }
      conexao = await MySqlConnection.connect(configuracaoMySQL);
      final resultado = await conexao.query(
        'DELETE FROM `tabelaCadastroCarros` WHERE `idCarro` = ?', [id],
      );
      if (resultado.affectedRows == 0) {
        await responder(requisicao.response, 404, {'erro': 'Carro nao encontrado.'});
      } else {
        await responder(requisicao.response, 200, {'mensagem': 'Carro excluido.'});
      }
      return;
    }
  } on FormatException {
    await responder(requisicao.response, 400, {'erro': 'JSON invalido.'});
  } on MySqlException catch (erro) {
    stderr.writeln('Erro MySQL: $erro');
    await responder(requisicao.response, 500, {
      'erro': 'Falha no banco de dados. Verifique conexao, placa duplicada ou servicos vinculados.'
    });
  } catch (erro) {
    stderr.writeln('Erro: $erro');
    await responder(requisicao.response, 500, {'erro': 'Erro interno no servidor.'});
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
