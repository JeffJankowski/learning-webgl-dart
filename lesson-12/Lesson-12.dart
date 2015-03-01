library lesson12;

import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:collection';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math' as math;


/**
 * based on:
 * http://learningwebgl.com/blog/?p=1359
 *
 * NOTE: Need to run from web server when using Chrome due to cross-site security issues loading texture images.
 *       Running from Firefox or Dartium's local server will work as well.
 */
class Lesson12 {

  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;

  webgl.Texture _moonTexture, _cubeTexture;

  webgl.Buffer _moonVertexTextureCoordBuffer, _cubeVertexTextureCoordBuffer;
  webgl.Buffer _moonVertexPositionBuffer, _cubeVertexPositionBuffer;
  webgl.Buffer _moonVertexNormalBuffer, _cubeVertexNormalBuffer;
  webgl.Buffer _moonVertexIndexBuffer, _cubeVertexIndexBuffer;

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
  webgl.UniformLocation _uPointLightingLocation;
  webgl.UniformLocation _uAmbientColor;
  webgl.UniformLocation _uPointLightingColor;

  InputElement _elmLighting;
  InputElement _elmAmbientR, _elmAmbientG, _elmAmbientB;
  InputElement _elmLightPositionX, _elmLightPositionY, _elmLightPositionZ;
  InputElement _elmPointR, _elmPointG, _elmPointB;

  double _lastTime = 0.0;
  int _moonVertexCount = 0, _cubeVertexCount = 0;

  static const int _latitudeBands = 30;
  static const int _longitudeBands = 30;
  static const int _radius = 2;

  double _moonAngle = 180.0;
  double _cubeAngle = 0.0;


  Lesson12(CanvasElement canvas) {
    _viewportWidth = canvas.width;
    _viewportHeight = canvas.height;
    _gl = canvas.getContext("experimental-webgl");

    _mvMatrix = new Matrix4.identity();
    _mvMatrixStack = new Queue<Matrix4>();
    _pMatrix = new Matrix4.identity();

    _initShaders();
    _initBuffers();
    _initTexture();

    _gl.clearColor(0.0, 0.0, 0.0, 1.0);
    _gl.enable(webgl.RenderingContext.DEPTH_TEST);

    _elmLighting = document.querySelector("#lighting");
    _elmAmbientR = document.querySelector("#ambientR");
    _elmAmbientG = document.querySelector("#ambientG");
    _elmAmbientB = document.querySelector("#ambientB");
    _elmLightPositionX = document.querySelector("#lightPositionX");
    _elmLightPositionY = document.querySelector("#lightPositionY");
    _elmLightPositionZ = document.querySelector("#lightPositionZ");
    _elmPointR = document.querySelector("#pointR");
    _elmPointG = document.querySelector("#pointG");
    _elmPointB = document.querySelector("#pointB");
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

    uniform vec3 uPointLightingLocation;
    uniform vec3 uPointLightingColor;

    uniform bool uUseLighting;

    varying vec2 vTextureCoord;
    varying vec3 vLightWeighting;

    void main(void) {
        vec4 mvPosition = uMVMatrix * vec4(aVertexPosition, 1.0);
        gl_Position = uPMatrix * mvPosition;
        vTextureCoord = aTextureCoord;

        if (!uUseLighting) {
            vLightWeighting = vec3(1.0, 1.0, 1.0);
        } else {
            vec3 lightDirection = normalize(uPointLightingLocation - mvPosition.xyz);

            vec3 transformedNormal = uNMatrix * aVertexNormal;
            float directionalLightWeighting = max(dot(transformedNormal, lightDirection), 0.0);
            vLightWeighting = uAmbientColor + uPointLightingColor * directionalLightWeighting;
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
    _uSampler = _gl.getUniformLocation(_shaderProgram, "uSampler");
    _uUseLighting = _gl.getUniformLocation(_shaderProgram, "uUseLighting");
    _uAmbientColor = _gl.getUniformLocation(_shaderProgram, "uAmbientColor");
    _uPointLightingLocation = _gl.getUniformLocation(_shaderProgram, "uPointLightingLocation");
    _uPointLightingColor = _gl.getUniformLocation(_shaderProgram, "uPointLightingColor");
  }


  void _initTexture() {
    _moonTexture = _gl.createTexture();
    ImageElement moonImage = new Element.tag('img');
    moonImage.onLoad.listen((e) {
      _handleLoadedTexture(_moonTexture, moonImage);
    });
    moonImage.src = "./moon.gif";

    _cubeTexture = _gl.createTexture();
    ImageElement cubeImage = new Element.tag('img');
    cubeImage.onLoad.listen((e) {
      _handleLoadedTexture(_cubeTexture, cubeImage);
    });
    cubeImage.src = "./crate.gif";
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

  void _initBuffers() {
    _cubeVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexPositionBuffer);
    List<double> vertices = [
        // Front face
        -1.0, -1.0,  1.0,
        1.0, -1.0,  1.0,
        1.0,  1.0,  1.0,
        -1.0,  1.0,  1.0,

        // Back face
        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
        1.0,  1.0, -1.0,
        1.0, -1.0, -1.0,

        // Top face
        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
        1.0,  1.0,  1.0,
        1.0,  1.0, -1.0,

        // Bottom face
        -1.0, -1.0, -1.0,
        1.0, -1.0, -1.0,
        1.0, -1.0,  1.0,
        -1.0, -1.0,  1.0,

        // Right face
        1.0, -1.0, -1.0,
        1.0,  1.0, -1.0,
        1.0,  1.0,  1.0,
        1.0, -1.0,  1.0,

        // Left face
        -1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
        -1.0,  1.0,  1.0,
        -1.0,  1.0, -1.0
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertices), webgl.RenderingContext.STATIC_DRAW);

    _cubeVertexNormalBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexNormalBuffer);
    List<double> vertexNormals = [
        // Front face
        0.0,  0.0,  1.0,
        0.0,  0.0,  1.0,
        0.0,  0.0,  1.0,
        0.0,  0.0,  1.0,

        // Back face
        0.0,  0.0, -1.0,
        0.0,  0.0, -1.0,
        0.0,  0.0, -1.0,
        0.0,  0.0, -1.0,

        // Top face
        0.0,  1.0,  0.0,
        0.0,  1.0,  0.0,
        0.0,  1.0,  0.0,
        0.0,  1.0,  0.0,

        // Bottom face
        0.0, -1.0,  0.0,
        0.0, -1.0,  0.0,
        0.0, -1.0,  0.0,
        0.0, -1.0,  0.0,

        // Right face
        1.0,  0.0,  0.0,
        1.0,  0.0,  0.0,
        1.0,  0.0,  0.0,
        1.0,  0.0,  0.0,

        // Left face
        -1.0,  0.0,  0.0,
        -1.0,  0.0,  0.0,
        -1.0,  0.0,  0.0,
        -1.0,  0.0,  0.0,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertexNormals), webgl.RenderingContext.STATIC_DRAW);

    _cubeVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexTextureCoordBuffer);
    var textureCoords = [
        // Front face
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,

        // Back face
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,

        // Top face
        0.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,

        // Bottom face
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,

        // Right face
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        0.0, 0.0,

        // Left face
        0.0, 0.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(textureCoords), webgl.RenderingContext.STATIC_DRAW);

    _cubeVertexIndexBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _cubeVertexIndexBuffer);
    List<int> cubeVertexIndices = [
        0, 1, 2,      0, 2, 3,    // Front face
        4, 5, 6,      4, 6, 7,    // Back face
        8, 9, 10,     8, 10, 11,  // Top face
        12, 13, 14,   12, 14, 15, // Bottom face
        16, 17, 18,   16, 18, 19, // Right face
        20, 21, 22,   20, 22, 23  // Left face
    ];
    _gl.bufferData(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(cubeVertexIndices), webgl.RenderingContext.STATIC_DRAW);
    _cubeVertexCount = cubeVertexIndices.length;


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

        _moonVertexCount+=6;
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

      _gl.uniform3f(_uPointLightingLocation,
          double.parse(_elmLightPositionX.value, (s) => 0.0),
          double.parse(_elmLightPositionY.value, (s) => 0.0),
          double.parse(_elmLightPositionZ.value, (s) => -20.0));

      _gl.uniform3f(
          _uPointLightingColor,
          double.parse(_elmPointR.value, (s) => 0.8),
          double.parse(_elmPointG.value, (s) => 0.8),
          double.parse(_elmPointB.value, (s) => 0.8));
    }

    _mvMatrix = new Matrix4.identity();

    _mvMatrix.translate(0.0, 0.0, -20.0);

    _mvPushMatrix();
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), _degToRad(_moonAngle));
    _mvMatrix.translate(new Vector3(5.0, 0.0, 0.0));
    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _moonTexture);
    _gl.uniform1i(_uSampler, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _moonVertexNormalBuffer);
    _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _moonVertexIndexBuffer);
    _setMatrixUniforms();
    _gl.drawElements(webgl.RenderingContext.TRIANGLES, _moonVertexCount, webgl.RenderingContext.UNSIGNED_SHORT, 0);
    _mvPopMatrix();


    _mvPushMatrix();
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), _degToRad(_cubeAngle));
    _mvMatrix.translate(new Vector3(5.0, 0.0, 0.0));
    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _cubeTexture);
    _gl.uniform1i(_uSampler, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexNormalBuffer);
    _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _cubeVertexIndexBuffer);
    _setMatrixUniforms();
    _gl.drawElements(webgl.RenderingContext.TRIANGLES, _cubeVertexCount, webgl.RenderingContext.UNSIGNED_SHORT, 0);
    _mvPopMatrix();


    _animate(time);

    // keep drawing
    window.requestAnimationFrame(this.render);
  }

  void _animate(double timeNow) {
    if (_lastTime != 0) {
      double elapsed = timeNow - _lastTime;

      _moonAngle += 0.05 * elapsed;
      _cubeAngle += 0.05 * elapsed;
    }
    _lastTime = timeNow;
  }


  double _degToRad(double degrees) {
    return degrees * math.PI / 180;
  }

  void start() {
    window.requestAnimationFrame(this.render);
  }

}


void main() {
  Lesson12 lesson = new Lesson12(document.querySelector('#drawHere'));
  lesson.start();
}
