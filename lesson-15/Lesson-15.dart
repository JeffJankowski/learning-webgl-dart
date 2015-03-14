library lesson15;

import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:collection';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math' as math;


/**
 * based on:
 * http://learningwebgl.com/blog/?p=1778
 *
 * NOTE: Need to run from web server when using Chrome due to cross-site security issues loading texture images.
 *       Running from Firefox or Dartium's local server will work as well.
 */
class Lesson15 {

  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;

  webgl.Texture _earthColorMapTexture;
  webgl.Texture _earthSpecularMapTexture;

  webgl.Buffer _sphereVertexTextureCoordBuffer;
  webgl.Buffer _sphereVertexPositionBuffer;
  webgl.Buffer _sphereVertexNormalBuffer;
  webgl.Buffer _sphereVertexIndexBuffer;

  Matrix4 _pMatrix;
  Matrix4 _mvMatrix;
  Queue<Matrix4> _mvMatrixStack;

  int _aVertexPosition;
  int _aTextureCoord;
  int _aVertexNormal;
  webgl.UniformLocation _uPMatrix;
  webgl.UniformLocation _uMVMatrix;
  webgl.UniformLocation _uNMatrix;
  webgl.UniformLocation _uColorMapSampler;
  webgl.UniformLocation _uSpecularMapSampler;
  webgl.UniformLocation _uUseLighting;
  webgl.UniformLocation _uUseColorMap;
  webgl.UniformLocation _uUseSpecularMap;
  webgl.UniformLocation _uAmbientColor;
  webgl.UniformLocation _uPointLightingLocation;
  webgl.UniformLocation _uPointLightingSpecularColor;
  webgl.UniformLocation _uPointLightingDiffuseColor;

  InputElement _elmLighting, _elmSpecularMap, _elmColorMap;
  InputElement _elmAmbientR, _elmAmbientG, _elmAmbientB;
  InputElement _elmLightPositionX, _elmLightPositionY, _elmLightPositionZ;
  InputElement _elmDiffuseR, _elmDiffuseG, _elmDiffuseB;
  InputElement _elmSpecularR, _elmSpecularG, _elmSpecularB;

  double _lastTime = 0.0;

  double _earthAngle = 180.0;
  int _sphereVertexCount = 0;

  static const int _latitudeBands = 30;
  static const int _longitudeBands = 30;
  static const int _radius = 13;


  Lesson15(CanvasElement canvas) {
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
    _elmSpecularMap = document.querySelector("#specular-map");
    _elmColorMap = document.querySelector("#color-map");
    _elmAmbientR = document.querySelector("#ambientR");
    _elmAmbientG = document.querySelector("#ambientG");
    _elmAmbientB = document.querySelector("#ambientB");
    _elmLightPositionX = document.querySelector("#lightPositionX");
    _elmLightPositionY = document.querySelector("#lightPositionY");
    _elmLightPositionZ = document.querySelector("#lightPositionZ");
    _elmDiffuseR = document.querySelector("#diffuseR");
    _elmDiffuseG = document.querySelector("#diffuseG");
    _elmDiffuseB = document.querySelector("#diffuseB");
    _elmSpecularR = document.querySelector("#specularR");
    _elmSpecularG = document.querySelector("#specularG");
    _elmSpecularB = document.querySelector("#specularB");
  }
  
  void _initShaders() {

    String vsSource = """
    attribute vec3 aVertexPosition;
    attribute vec3 aVertexNormal;
    attribute vec2 aTextureCoord;

    uniform mat4 uMVMatrix;
    uniform mat4 uPMatrix;
    uniform mat3 uNMatrix;

    varying vec2 vTextureCoord;
    varying vec3 vTransformedNormal;
    varying vec4 vPosition;


    void main(void) {
        vPosition = uMVMatrix * vec4(aVertexPosition, 1.0);
        gl_Position = uPMatrix * vPosition;
        vTextureCoord = aTextureCoord;
        vTransformedNormal = uNMatrix * aVertexNormal;
    }
    """;

    String fsSource = """
    precision mediump float;

    varying vec2 vTextureCoord;
    varying vec3 vTransformedNormal;
    varying vec4 vPosition;

    uniform bool uUseColorMap;
    uniform bool uUseSpecularMap;
    uniform bool uUseLighting;

    uniform vec3 uAmbientColor;

    uniform vec3 uPointLightingLocation;
    uniform vec3 uPointLightingSpecularColor;
    uniform vec3 uPointLightingDiffuseColor;

    uniform sampler2D uColorMapSampler;
    uniform sampler2D uSpecularMapSampler;


    void main(void) {
        vec3 lightWeighting;
        if (!uUseLighting) {
            lightWeighting = vec3(1.0, 1.0, 1.0);
        } else {
            vec3 lightDirection = normalize(uPointLightingLocation - vPosition.xyz);
            vec3 normal = normalize(vTransformedNormal);

            float specularLightWeighting = 0.0;
            float shininess = 32.0;
            if (uUseSpecularMap) {
                shininess = texture2D(uSpecularMapSampler, vec2(vTextureCoord.s, vTextureCoord.t)).r * 255.0;
            }
            if (shininess < 255.0) {
                vec3 eyeDirection = normalize(-vPosition.xyz);
                vec3 reflectionDirection = reflect(-lightDirection, normal);

                specularLightWeighting = pow(max(dot(reflectionDirection, eyeDirection), 0.0), shininess);
            }

            float diffuseLightWeighting = max(dot(normal, lightDirection), 0.0);
            lightWeighting = uAmbientColor
                + uPointLightingSpecularColor * specularLightWeighting
                + uPointLightingDiffuseColor * diffuseLightWeighting;
        }

        vec4 fragmentColor;
        if (uUseColorMap) {
            fragmentColor = texture2D(uColorMapSampler, vec2(vTextureCoord.s, vTextureCoord.t));
        } else {
            fragmentColor = vec4(1.0, 1.0, 1.0, 1.0);
        }
        gl_FragColor = vec4(fragmentColor.rgb * lightWeighting, fragmentColor.a);
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

    // attach shaders to a webgl program
    webgl.Program _shaderProgram = _gl.createProgram();
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
    _uColorMapSampler = _gl.getUniformLocation(_shaderProgram, "uColorMapSampler");
    _uSpecularMapSampler = _gl.getUniformLocation(_shaderProgram, "uSpecularMapSampler");
    _uUseSpecularMap = _gl.getUniformLocation(_shaderProgram, "uUseSpecularMap");
    _uUseLighting = _gl.getUniformLocation(_shaderProgram, "uUseLighting");
    _uUseColorMap = _gl.getUniformLocation(_shaderProgram, "uUseColorMap");
    _uAmbientColor = _gl.getUniformLocation(_shaderProgram, "uAmbientColor");
    _uPointLightingLocation = _gl.getUniformLocation(_shaderProgram, "uPointLightingLocation");
    _uPointLightingSpecularColor = _gl.getUniformLocation(_shaderProgram, "uPointLightingSpecularColor");
    _uPointLightingDiffuseColor = _gl.getUniformLocation(_shaderProgram, "uPointLightingDiffuseColor");
  }


  void _initTexture() {
    _earthColorMapTexture = _gl.createTexture();
    ImageElement earthImage = new Element.tag('img');
    earthImage.onLoad.listen((e) {
      _handleLoadedTexture(_earthColorMapTexture, earthImage);
    });
    earthImage.src = "./earth.jpg";

    _earthSpecularMapTexture = _gl.createTexture();
    ImageElement specularImage = new Element.tag('img');
    specularImage.onLoad.listen((e) {
      _handleLoadedTexture(_earthSpecularMapTexture, specularImage);
    });
    specularImage.src = "./earth-specular.gif";
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
      }
    }
    _sphereVertexCount = indexData.length;

    _sphereVertexNormalBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _sphereVertexNormalBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(normalData), webgl.RenderingContext.STATIC_DRAW);

    _sphereVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _sphereVertexTextureCoordBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(textureCoordData), webgl.RenderingContext.STATIC_DRAW);

    _sphereVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _sphereVertexPositionBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertexPositionData), webgl.RenderingContext.STATIC_DRAW);

    _sphereVertexIndexBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _sphereVertexIndexBuffer);
    _gl.bufferData(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(indexData), webgl.RenderingContext.STATIC_DRAW);
  }



  void drawScene(double time) {
    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);

    // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
    _pMatrix = makePerspectiveMatrix(radians(45.0), _viewportWidth / _viewportHeight, 0.1, 100.0);

    _gl.uniform1i(_uUseSpecularMap, _elmSpecularMap.checked ? 1 : 0);
    _gl.uniform1i(_uUseColorMap, _elmColorMap.checked ? 1 : 0);
    _gl.uniform1i(_uUseLighting, _elmLighting.checked ? 1 : 0); // must be int, not bool
    if (_elmLighting.checked) {

      _gl.uniform3f(
          _uAmbientColor,
          double.parse(_elmAmbientR.value, (s) => 0.2),
          double.parse(_elmAmbientG.value, (s) => 0.2),
          double.parse(_elmAmbientB.value, (s) => 0.2));

      _gl.uniform3f(
          _uPointLightingLocation,
          double.parse(_elmLightPositionX.value, (s) => -10.0),
          double.parse(_elmLightPositionY.value, (s) => 4.0),
          double.parse(_elmLightPositionZ.value, (s) => -20.0));

      _gl.uniform3f(
          _uPointLightingSpecularColor,
          double.parse(_elmSpecularR.value, (s) => 0.8),
          double.parse(_elmSpecularG.value, (s) => 0.8),
          double.parse(_elmSpecularB.value, (s) => 0.8));

      _gl.uniform3f(
          _uPointLightingDiffuseColor,
          double.parse(_elmDiffuseR.value, (s) => 0.8),
          double.parse(_elmDiffuseG.value, (s) => 0.8),
          double.parse(_elmDiffuseB.value, (s) => 0.8));
    }

    _mvMatrix = new Matrix4.identity();

    _mvMatrix.translate(0.0, 0.0, -40.0);
    _mvMatrix.rotate(new Vector3(1.0, 0.0, -1.0), radians(23.4));
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(_earthAngle));

    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _earthColorMapTexture);
    _gl.uniform1i(_uColorMapSampler, 0);

    _gl.activeTexture(webgl.RenderingContext.TEXTURE1);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _earthSpecularMapTexture);
    _gl.uniform1i(_uSpecularMapSampler, 1);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _sphereVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _sphereVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _sphereVertexNormalBuffer);
    _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _sphereVertexIndexBuffer);
    _setMatrixUniforms();
    _gl.drawElements(webgl.RenderingContext.TRIANGLES, _sphereVertexCount, webgl.RenderingContext.UNSIGNED_SHORT, 0);

    _animate(time);

    // keep drawing
    window.requestAnimationFrame(this.drawScene);
  }

  void _animate(double timeNow) {
    if (_lastTime != 0) {
      double elapsed = timeNow - _lastTime;

      _earthAngle += 0.05 * elapsed;
    }
    _lastTime = timeNow;
  }


  void start() {
    window.requestAnimationFrame(this.drawScene);
  }

}


void main() {
  Lesson15 lesson = new Lesson15(document.querySelector('#drawHere'));
  lesson.start();
}
