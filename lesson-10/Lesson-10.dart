library lesson10;

import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:collection';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math' as math;


/**
 * based on:
 * http://learningwebgl.com/blog/?p=1067
 *
 * NOTE: Need to run from web server when using Chrome due to cross-site security issues loading texture images.
 *       Running from Firefox or Dartium's local server will work as well.
 */
class Lesson10 {

  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;

  webgl.Texture _texture;

  webgl.Buffer _worldVertexTextureCoordBuffer;
  webgl.Buffer _worldVertexPositionBuffer;

  Matrix4 _pMatrix;
  Matrix4 _mvMatrix;
  //Apparently Queue and Stack are interchangeable in Dart... so yeah
  Queue<Matrix4> _mvMatrixStack;

  int _aVertexPosition;
  int _aTextureCoord;
  webgl.UniformLocation _uPMatrix;
  webgl.UniformLocation _uMVMatrix;
  webgl.UniformLocation _uSampler;
  webgl.UniformLocation _uColor;

  double _pitch = 0.0, _pitchRate = 0.0;
  double _yaw = 0.0, _yawRate = 0.0;
  double _xPos = 0.0, _yPos = 0.4, _zPos = 0.0;
  double _speed = 0.0;
  // Used to make us "jog" up and down as we move forward.
  double _joggingAngle = 0.0;

  double _lastTime = 0.0;
  List<bool> _currentlyPressedKeys;

  int _vertexCount;


  Lesson10(CanvasElement canvas) {
    // weird, but without specifying size this array throws exception on []
    _currentlyPressedKeys = new List<bool>(128);
    _viewportWidth = canvas.width;
    _viewportHeight = canvas.height;
    _gl = canvas.getContext("experimental-webgl");

    _mvMatrix = new Matrix4.identity();
    _mvMatrixStack = new Queue<Matrix4>();
    _pMatrix = new Matrix4.identity();

    _initShaders();
    _initTexture();
    _initWorld();

    _gl.clearColor(0.0, 0.0, 0.0, 1.0);
    _gl.enable(webgl.RenderingContext.DEPTH_TEST);

    document.onKeyDown.listen(this._handleKeyDown);
    document.onKeyUp.listen(this._handleKeyUp);
  }


  void _initShaders() {
    String vsSource = """
    attribute vec3 aVertexPosition;
    attribute vec2 aTextureCoord;

    uniform mat4 uMVMatrix;
    uniform mat4 uPMatrix;

    varying vec2 vTextureCoord;

    void main(void) {
        gl_Position = uPMatrix * uMVMatrix * vec4(aVertexPosition, 1.0);
        vTextureCoord = aTextureCoord;
    }
    """;

    String fsSource = """
    precision mediump float;

    varying vec2 vTextureCoord;

    uniform sampler2D uSampler;

    void main(void) {
        gl_FragColor = texture2D(uSampler, vec2(vTextureCoord.s, vTextureCoord.t));
    }
    """;

    // vertex shader compilation
    webgl.Shader vs = _gl.createShader(webgl.RenderingContext.VERTEX_SHADER);
    _gl.shaderSource(vs, vsSource);
    _gl.compileShader(vs);

    // fragment shader compilation
    webgl.Shader fs = _gl.createShader(webgl.RenderingContext.FRAGMENT_SHADER);
    _gl.shaderSource(fs, fsSource);
    _gl.compileShader(fs);

    // attach shaders to a webgl. program
    _shaderProgram = _gl.createProgram();
    _gl.attachShader(_shaderProgram, vs);
    _gl.attachShader(_shaderProgram, fs);
    _gl.linkProgram(_shaderProgram);
    _gl.useProgram(_shaderProgram);

    /**
     * Check if shaders were compiled properly. This is probably the most painful part
     * since there's no way to "debug" shader compilation
     */
    if (!_gl.getShaderParameter(vs, webgl.RenderingContext.COMPILE_STATUS)) {
      print(_gl.getShaderInfoLog(vs));
    }

    if (!_gl.getShaderParameter(fs, webgl.RenderingContext.COMPILE_STATUS)) {
      print(_gl.getShaderInfoLog(fs));
    }

    if (!_gl.getProgramParameter(_shaderProgram, webgl.RenderingContext.LINK_STATUS)) {
      print(_gl.getProgramInfoLog(_shaderProgram));
    }

    _aVertexPosition = _gl.getAttribLocation(_shaderProgram, "aVertexPosition");
    _gl.enableVertexAttribArray(_aVertexPosition);

    _aTextureCoord = _gl.getAttribLocation(_shaderProgram, "aTextureCoord");
    _gl.enableVertexAttribArray(_aTextureCoord);

    _uPMatrix = _gl.getUniformLocation(_shaderProgram, "uPMatrix");
    _uMVMatrix = _gl.getUniformLocation(_shaderProgram, "uMVMatrix");
    _uSampler = _gl.getUniformLocation(_shaderProgram, "uSampler");
    _uColor = _gl.getUniformLocation(_shaderProgram, "uColor");
  }


  void _initTexture() {
    _texture = _gl.createTexture();
    ImageElement image = new Element.tag('img');
    image.onLoad.listen((e) {
      _handleLoadedTexture(_texture, image);
    });
    image.src = "./mud.gif";
  }

  void _mvPushMatrix() {
    _mvMatrixStack.addLast(new Matrix4.copy(_mvMatrix));
  }

  void _mvPopMatrix() {
    if (_mvMatrixStack.isEmpty) {
      throw "Model-View matrix stack is empty!";
    }

    _mvMatrix = _mvMatrixStack.removeLast();
  }

  void _handleLoadedTexture(webgl.Texture texture, ImageElement img) {
    _gl.pixelStorei(webgl.RenderingContext.UNPACK_FLIP_Y_WEBGL, 1); // second argument must be an int (no boolean)

    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, texture);
    _gl.texImage2D(webgl.RenderingContext.TEXTURE_2D, 0, webgl.RenderingContext.RGBA, webgl.RenderingContext.RGBA, webgl.RenderingContext.UNSIGNED_BYTE, img);
    _gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MAG_FILTER, webgl.RenderingContext.LINEAR);
    _gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MIN_FILTER, webgl.RenderingContext.LINEAR);

    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, null);
  }

  void _setMatrixUniforms() {
    _gl.uniformMatrix4fv(_uPMatrix, false, _pMatrix.storage);
    _gl.uniformMatrix4fv(_uMVMatrix, false, _mvMatrix.storage);
  }

  void _handleLoadedWorld(String data) {
    _vertexCount = 0;
    List<double> vertexPositions = new List(), vertexTextureCoords = new List();

    List<String> lines = data.split('\n');
    for (String line in lines) {
      List<String> vals = line.replaceAll(new RegExp('^ +'), "").split(new RegExp(' +'));
      if (vals.length == 5 && vals[0] != "//") {
        // It is a line describing a vertex; get X, Y and Z first
        vertexPositions.add(double.parse(vals[0]));
        vertexPositions.add(double.parse(vals[1]));
        vertexPositions.add(double.parse(vals[2]));

        // And then the texture coords
        vertexTextureCoords.add(double.parse(vals[3]));
        vertexTextureCoords.add(double.parse(vals[4]));

        _vertexCount += 1;
      }
    }

    _worldVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _worldVertexPositionBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertexPositions), webgl.RenderingContext.STATIC_DRAW);

    _worldVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _worldVertexTextureCoordBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertexTextureCoords), webgl.RenderingContext.STATIC_DRAW);

    document.getElementById("loadingtext").text = "";
  }

  void _initWorld() {
    // Dart makes this way easier compared to JS <3
    HttpRequest.getString("world.txt")
    .then( (String response) {
      _handleLoadedWorld(response);
    })
    .catchError((Error e) {
      print(e.toString());
    });
  }


  void drawScene(double time) {
    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);

    if (_worldVertexTextureCoordBuffer != null && _worldVertexPositionBuffer != null) {
      // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
      _pMatrix = makePerspectiveMatrix(radians(45.0), _viewportWidth / _viewportHeight, 0.1, 100.0);

      _mvMatrix = new Matrix4.identity();
      _mvMatrix.rotate(new Vector3(1.0, 0.0, 0.0), radians(-_pitch));
      _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(-_yaw));
      _mvMatrix.translate(-_xPos, -_yPos, -_zPos);

      _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
      _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _texture);
      _gl.uniform1i(_uSampler, 0);

      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _worldVertexTextureCoordBuffer);
      _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _worldVertexPositionBuffer);
      _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

      _setMatrixUniforms();
      _gl.drawArrays(webgl.RenderingContext.TRIANGLES, 0, _vertexCount);

      _animate(time);
      _handleKeys();
    }

    // keep drawing
    window.requestAnimationFrame(this.drawScene);
  }

  void _handleKeyDown(KeyboardEvent event) {
    _currentlyPressedKeys[event.keyCode] = true;
  }

  void _handleKeyUp(KeyboardEvent event) {
    _currentlyPressedKeys[event.keyCode] = false;
  }

  void _animate(double timeNow) {
    if (_lastTime != 0) {
      double elapsed = timeNow - _lastTime;

      if (_speed != 0) {
        _xPos -= math.sin(radians(_yaw)) * _speed * elapsed;
        _zPos -= math.cos(radians(_yaw)) * _speed * elapsed;

        _joggingAngle += elapsed * 0.6; // 0.6 "fiddle factor" - makes it feel more realistic :-)
        _yPos = math.sin(radians(_joggingAngle)) / 20 + 0.4;
      }

      _yaw += _yawRate * elapsed;
      _pitch += _pitchRate * elapsed;

    }
    _lastTime = timeNow;
  }

  void _handleKeys() {
    if (_currentlyPressedKeys[33] != null && _currentlyPressedKeys[33]) {
      // Page Up
      _pitchRate = 0.1;
    } else if (_currentlyPressedKeys[34] != null && _currentlyPressedKeys[34]) {
      // Page Down
      _pitchRate = -0.1;
    } else {
      _pitchRate = 0.0;
    }

    if ((_currentlyPressedKeys[37] != null && _currentlyPressedKeys[37]) ||
    (_currentlyPressedKeys[65] != null && _currentlyPressedKeys[65])) {
      // Left cursor key or A
      _yawRate = 0.1;
    } else if ((_currentlyPressedKeys[39] != null && _currentlyPressedKeys[39]) ||
    (_currentlyPressedKeys[68] != null && _currentlyPressedKeys[68])) {
      // Right cursor key or D
      _yawRate = -0.1;
    } else {
      _yawRate = 0.0;
    }

    if ((_currentlyPressedKeys[38] != null && _currentlyPressedKeys[38]) ||
    (_currentlyPressedKeys[87] != null && _currentlyPressedKeys[87])) {
      // Up cursor key or W
      _speed = 0.003;
    } else if (_currentlyPressedKeys[40] != null && _currentlyPressedKeys[40] ||
    (_currentlyPressedKeys[83] != null && _currentlyPressedKeys[83])) {
      // Down cursor key
      _speed = -0.003;
    } else {
      _speed = 0.0;
    }
  }

  void start() {
    window.requestAnimationFrame(this.drawScene);
  }

}


void main() {
  Lesson10 lesson = new Lesson10(document.querySelector('#drawHere'));
  lesson.start();
}
