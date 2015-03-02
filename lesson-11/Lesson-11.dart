library lesson11;

import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:collection';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math' as math;


/**
 * based on:
 * http://learningwebgl.com/blog/?p=1253
 *
 * NOTE: Need to run from web server when using Chrome due to cross-site security issues loading texture images.
 *       Running from Firefox or Dartium's local server will work as well.
 */
class Lesson11 {

  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;

  webgl.Texture _texture;

  webgl.Buffer _moonVertexTextureCoordBuffer;
  webgl.Buffer _moonVertexPositionBuffer;
  webgl.Buffer _moonVertexNormalBuffer;
  webgl.Buffer _moonVertexIndexBuffer;

  Matrix4 _pMatrix;
  Matrix4 _mvMatrix;
  //Apparently Queue and Stack are interchangeable in Dart... so yeah
  Queue<Matrix4> _mvMatrixStack;

  int _aVertexPosition;
  int _aTextureCoord;
  int _aVertexNormal;
  webgl.UniformLocation _uPMatrix;
  webgl.UniformLocation _uMVMatrix;
  webgl.UniformLocation _uNMatrix;
  webgl.UniformLocation _uSampler;
  webgl.UniformLocation _uColor;
  webgl.UniformLocation _uUseLighting;
  webgl.UniformLocation _uLightingDirection;
  webgl.UniformLocation _uAmbientColor;
  webgl.UniformLocation _uDirectionalColor;

  InputElement _elmLighting;
  InputElement _elmAmbientR, _elmAmbientG, _elmAmbientB;
  InputElement _elmLightDirectionX, _elmLightDirectionY, _elmLightDirectionZ;
  InputElement _elmDirectionalR, _elmDirectionalG, _elmDirectionalB;

  double _lastTime = 0.0;
  int _vertexCount = 0;

  static const int _latitudeBands = 30;
  static const int _longitudeBands = 30;
  static const int _radius = 2;

  bool _mouseDown = false;
  int _lastMouseX;
  int _lastMouseY;

  Matrix4 _moonRotationMatrix;


  Lesson11(CanvasElement canvas) {
    _viewportWidth = canvas.width;
    _viewportHeight = canvas.height;
    _gl = canvas.getContext("experimental-webgl");

    _mvMatrix = new Matrix4.identity();
    _mvMatrixStack = new Queue<Matrix4>();
    _pMatrix = new Matrix4.identity();

    _moonRotationMatrix = new Matrix4.identity();

    _initShaders();
    _initBuffers();
    _initTexture();

    _gl.clearColor(0.0, 0.0, 0.0, 1.0);
    _gl.enable(webgl.RenderingContext.DEPTH_TEST);

    canvas.onMouseDown.listen(this._handleMouseDown);
    document.onMouseUp.listen(this._handleMouseUp);
    document.onMouseMove.listen(this._handleMouseMove);

    _elmLighting = document.querySelector("#lighting");
    _elmAmbientR = document.querySelector("#ambientR");
    _elmAmbientG = document.querySelector("#ambientG");
    _elmAmbientB = document.querySelector("#ambientB");
    _elmLightDirectionX = document.querySelector("#lightDirectionX");
    _elmLightDirectionY = document.querySelector("#lightDirectionY");
    _elmLightDirectionZ = document.querySelector("#lightDirectionZ");
    _elmDirectionalR = document.querySelector("#directionalR");
    _elmDirectionalG = document.querySelector("#directionalG");
    _elmDirectionalB = document.querySelector("#directionalB");
  }


  void _initShaders() {
    // vertex shader source code. uPosition is our variable that we'll
    // use to create animation
    String vsSource = """
    attribute vec3 aVertexPosition;
    attribute vec3 aVertexNormal;
    attribute vec2 aTextureCoord;

    uniform mat4 uMVMatrix;
    uniform mat4 uPMatrix;
    uniform mat3 uNMatrix;

    uniform vec3 uAmbientColor;

    uniform vec3 uLightingDirection;
    uniform vec3 uDirectionalColor;

    uniform bool uUseLighting;

    varying vec2 vTextureCoord;
    varying vec3 vLightWeighting;

    void main(void) {
        gl_Position = uPMatrix * uMVMatrix * vec4(aVertexPosition, 1.0);
        vTextureCoord = aTextureCoord;

        if (!uUseLighting) {
            vLightWeighting = vec3(1.0, 1.0, 1.0);
        } else {
            vec3 transformedNormal = uNMatrix * aVertexNormal;
            float directionalLightWeighting = max(dot(transformedNormal, uLightingDirection), 0.0);
            vLightWeighting = uAmbientColor + uDirectionalColor * directionalLightWeighting;
        }
    }
    """;

    // fragment shader source code. uColor is our variable that we'll
    // use to animate color
    String fsSource = """
    precision mediump float;

    varying vec2 vTextureCoord;
    varying vec3 vLightWeighting;

    uniform sampler2D uSampler;

    void main(void) {
        vec4 textureColor = texture2D(uSampler, vec2(vTextureCoord.s, vTextureCoord.t));
        gl_FragColor = vec4(textureColor.rgb * vLightWeighting, textureColor.a);
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

    _aVertexNormal = _gl.getAttribLocation(_shaderProgram, "aVertexNormal");
    _gl.enableVertexAttribArray(_aVertexNormal);

    _uPMatrix = _gl.getUniformLocation(_shaderProgram, "uPMatrix");
    _uMVMatrix = _gl.getUniformLocation(_shaderProgram, "uMVMatrix");
    _uNMatrix = _gl.getUniformLocation(_shaderProgram, "uNMatrix");
    _uSampler = _gl.getUniformLocation(_shaderProgram, "uSampler");
    _uColor = _gl.getUniformLocation(_shaderProgram, "uColor");
    _uUseLighting = _gl.getUniformLocation(_shaderProgram, "uUseLighting");
    _uAmbientColor = _gl.getUniformLocation(_shaderProgram, "uAmbientColor");
    _uLightingDirection = _gl.getUniformLocation(_shaderProgram, "uLightingDirection");
    _uDirectionalColor = _gl.getUniformLocation(_shaderProgram, "uDirectionalColor");
  }


  void _initTexture() {
    _texture = _gl.createTexture();
    ImageElement image = new Element.tag('img');
    image.onLoad.listen((e) {
      _handleLoadedTexture(_texture, image);
    });
    image.src = "./moon.gif";
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
    _gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MIN_FILTER, webgl.RenderingContext.LINEAR_MIPMAP_NEAREST);
    _gl.generateMipmap(webgl.RenderingContext.TEXTURE_2D);

    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, null);
  }

  void _setMatrixUniforms() {
    _gl.uniformMatrix4fv(_uPMatrix, false, _pMatrix.storage);
    _gl.uniformMatrix4fv(_uMVMatrix, false, _mvMatrix.storage);

    Matrix3 normalMatrix = _mvMatrix.getRotation();
    normalMatrix.invert();
    normalMatrix.transpose();
    _gl.uniformMatrix3fv(_uNMatrix, false, normalMatrix.storage);
  }

  void _handleMouseDown(MouseEvent event) {
    _mouseDown = true;
    _lastMouseX = event.client.x;
    _lastMouseY = event.client.y;
  }

  void _handleMouseUp(MouseEvent event) {
    _mouseDown = false;
  }

  void _handleMouseMove(MouseEvent event) {
    if (!_mouseDown) {
      return;
    }

    int newX = event.client.x;
    int newY = event.client.y;

    int deltaX = newX - _lastMouseX;
    Matrix4 newRotationMatrix = new Matrix4.identity();
    newRotationMatrix.rotate(new Vector3(0.0, 1.0, 0.0), _degToRad(deltaX / 10.0));

    int deltaY = newY - _lastMouseY;
    newRotationMatrix.rotate(new Vector3(1.0, 0.0, 0.0), _degToRad(deltaY / 10.0));

    // Gotcha here: matrix multiplication is NOT commutative, we need to multiply newRotationMatrix by _moonRotationMatrix
    // This will modify newRotationMatrix, but we don't care, just store the result to the global rotation matrix
    _moonRotationMatrix = newRotationMatrix.multiply(_moonRotationMatrix);

    _lastMouseX = newX;
    _lastMouseY = newY;
  }

  void _initBuffers() {
    List<double> vertexPositionData = [];
    List<double> normalData = [];
    List<double> textureCoordData = [];
    List<int> indexData = [];

    for (int latNumber = 0; latNumber <= _latitudeBands; latNumber++) {
      double theta = latNumber * math.PI / _latitudeBands;
      double sinTheta = math.sin(theta);
      double cosTheta = math.cos(theta);

      for (int longNumber = 0; longNumber <= _longitudeBands; longNumber++) {
        double phi = longNumber * 2 * math.PI / _longitudeBands;
        double sinPhi = math.sin(phi);
        double cosPhi = math.cos(phi);

        double x = cosPhi * sinTheta;
        double y = cosTheta;
        double z = sinPhi * sinTheta;
        double u = 1 - (longNumber / _longitudeBands);
        double v = 1 - (latNumber / _latitudeBands);

        normalData.add(x);
        normalData.add(y);
        normalData.add(z);
        textureCoordData.add(u);
        textureCoordData.add(v);
        vertexPositionData.add(_radius * x);
        vertexPositionData.add(_radius * y);
        vertexPositionData.add(_radius * z);
      }
    }

    for (int latNumber = 0; latNumber < _latitudeBands; latNumber++) {
      for (int longNumber = 0; longNumber < _longitudeBands; longNumber++) {
        int first = (latNumber * (_longitudeBands + 1)) + longNumber;
        int second = first + _longitudeBands + 1;
        indexData.add(first);
        indexData.add(second);
        indexData.add(first + 1);

        indexData.add(second);
        indexData.add(second + 1);
        indexData.add(first + 1);

        _vertexCount+=6;
      }
    }

    _moonVertexNormalBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexNormalBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(normalData), webgl.RenderingContext.STATIC_DRAW);

    _moonVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexTextureCoordBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(textureCoordData), webgl.RenderingContext.STATIC_DRAW);

    _moonVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexPositionBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertexPositionData), webgl.RenderingContext.STATIC_DRAW);

    _moonVertexIndexBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _moonVertexIndexBuffer);
    _gl.bufferData(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(indexData), webgl.RenderingContext.STATIC_DRAW);
  }


  void render(double time) {
    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);

    // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
    _pMatrix = makePerspectiveMatrix(radians(45.0), _viewportWidth / _viewportHeight, 0.1, 100.0);

    // draw lighting?
    _gl.uniform1i(_uUseLighting, _elmLighting.checked ? 1 : 0); // must be int, not bool
    if (_elmLighting.checked) {

      _gl.uniform3f(
          _uAmbientColor,
          double.parse(_elmAmbientR.value, (s) => 0.2),
          double.parse(_elmAmbientG.value, (s) => 0.2),
          double.parse(_elmAmbientB.value, (s) => 0.2));

      Vector3 lightingDirection = new Vector3(
          double.parse(_elmLightDirectionX.value, (s) => -1.0),
          double.parse(_elmLightDirectionY.value, (s) => -1.0),
          double.parse(_elmLightDirectionZ.value, (s) => -1.0));
      Vector3 adjustedLD = lightingDirection.normalize();
      adjustedLD.scale(-1.0);
      _gl.uniform3fv(_uLightingDirection, adjustedLD.storage);

      _gl.uniform3f(
          _uDirectionalColor,
          double.parse(_elmDirectionalR.value, (s) => 0.8),
          double.parse(_elmDirectionalG.value, (s) => 0.8),
          double.parse(_elmDirectionalB.value, (s) => 0.8));
    }

    _mvMatrix = new Matrix4.identity();

    _mvMatrix.translate(0.0, 0.0, -6.0);

    _mvMatrix.multiply(_moonRotationMatrix);

    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _texture);
    _gl.uniform1i(_uSampler, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexNormalBuffer);
    _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _moonVertexIndexBuffer);
    _setMatrixUniforms();
    _gl.drawElements(webgl.RenderingContext.TRIANGLES, _vertexCount, webgl.RenderingContext.UNSIGNED_SHORT, 0);

    // keep drawing
    window.requestAnimationFrame(this.render);
  }


  double _degToRad(double degrees) {
    return degrees * math.PI / 180;
  }

  void start() {
    window.requestAnimationFrame(this.render);
  }

}


void main() {
  Lesson11 lesson = new Lesson11(document.querySelector('#drawHere'));
  lesson.start();
}
