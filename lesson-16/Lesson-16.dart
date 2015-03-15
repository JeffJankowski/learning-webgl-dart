library lesson16;

import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:collection';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';


/**
 * based on:
 * http://learningwebgl.com/blog/?p=1658
 *
 * NOTE: Need to run from web server when using Chrome due to cross-site security issues loading texture images.
 *       Running from Firefox or Dartium's local server will work as well.
 */
class Lesson16 {

  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;

  webgl.Texture _crateTexture, _moonTexture;

  webgl.Framebuffer _rttFramebuffer;
  webgl.Texture _rttTexture;

  webgl.Buffer _moonVertexTextureCoordBuffer;
  webgl.Buffer _moonVertexPositionBuffer;
  webgl.Buffer _moonVertexNormalBuffer;
  webgl.Buffer _moonVertexIndexBuffer;

  webgl.Buffer _cubeVertexTextureCoordBuffer;
  webgl.Buffer _cubeVertexPositionBuffer;
  webgl.Buffer _cubeVertexNormalBuffer;
  webgl.Buffer _cubeVertexIndexBuffer;

  webgl.Buffer _laptopVertexTextureCoordBuffer;
  webgl.Buffer _laptopVertexPositionBuffer;
  webgl.Buffer _laptopVertexNormalBuffer;
  webgl.Buffer _laptopVertexIndexBuffer;

  webgl.Buffer _laptopScreenVertexTextureCoordBuffer;
  webgl.Buffer _laptopScreenVertexPositionBuffer;
  webgl.Buffer _laptopScreenVertexNormalBuffer;

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
  webgl.UniformLocation _uUseTextures;
  webgl.UniformLocation _uShowSpecularHighlights;
  webgl.UniformLocation _uPointLightingLocation;
  webgl.UniformLocation _uPointLightingSpecularColor;
  webgl.UniformLocation _uPointLightingDiffuseColor;
  webgl.UniformLocation _uMaterialShininess;
  webgl.UniformLocation _uMaterialAmbientColor;
  webgl.UniformLocation _uMaterialDiffuseColor;
  webgl.UniformLocation _uMaterialSpecularColor;
  webgl.UniformLocation _uMaterialEmissiveColor;
  webgl.UniformLocation _uAmbientLightingColor;

  double _lastTime = 0.0;
  int _moonVertexCount = 0, _cubeVertexCount = 0, _laptopVertexCount = 0;

  static const int _latitudeBands = 30;
  static const int _longitudeBands = 30;
  static const int _radius = 1;

  double _moonAngle = 180.0;
  double _cubeAngle = 0.0;
  double _laptopAngle = 0.0;

  double _laptopScreenAspectRatio = 1.66;


  Lesson16(CanvasElement canvas) {
    _viewportWidth = canvas.width;
    _viewportHeight = canvas.height;
    _gl = canvas.getContext("experimental-webgl");

    _mvMatrix = new Matrix4.identity();
    _mvMatrixStack = new Queue<Matrix4>();
    _pMatrix = new Matrix4.identity();

    _initTextureFramebuffer();
    _initShaders();
    _initBuffers();
    _initTextures();
    _loadLaptop();

    _gl.clearColor(0.0, 0.0, 0.0, 1.0);
    _gl.enable(webgl.RenderingContext.DEPTH_TEST);
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

    uniform vec3 uMaterialAmbientColor;
    uniform vec3 uMaterialDiffuseColor;
    uniform vec3 uMaterialSpecularColor;
    uniform float uMaterialShininess;
    uniform vec3 uMaterialEmissiveColor;

    uniform bool uShowSpecularHighlights;
    uniform bool uUseTextures;

    uniform vec3 uAmbientLightingColor;

    uniform vec3 uPointLightingLocation;
    uniform vec3 uPointLightingDiffuseColor;
    uniform vec3 uPointLightingSpecularColor;

    uniform sampler2D uSampler;


    void main(void) {
        vec3 ambientLightWeighting = uAmbientLightingColor;

        vec3 lightDirection = normalize(uPointLightingLocation - vPosition.xyz);
        vec3 normal = normalize(vTransformedNormal);

        vec3 specularLightWeighting = vec3(0.0, 0.0, 0.0);
        if (uShowSpecularHighlights) {
            vec3 eyeDirection = normalize(-vPosition.xyz);
            vec3 reflectionDirection = reflect(-lightDirection, normal);

            float specularLightBrightness = pow(max(dot(reflectionDirection, eyeDirection), 0.0), uMaterialShininess);
            specularLightWeighting = uPointLightingSpecularColor * specularLightBrightness;
        }

        float diffuseLightBrightness = max(dot(normal, lightDirection), 0.0);
        vec3 diffuseLightWeighting = uPointLightingDiffuseColor * diffuseLightBrightness;

        vec3 materialAmbientColor = uMaterialAmbientColor;
        vec3 materialDiffuseColor = uMaterialDiffuseColor;
        vec3 materialSpecularColor = uMaterialSpecularColor;
        vec3 materialEmissiveColor = uMaterialEmissiveColor;
        float alpha = 1.0;
        if (uUseTextures) {
            vec4 textureColor = texture2D(uSampler, vec2(vTextureCoord.s, vTextureCoord.t));
            materialAmbientColor = materialAmbientColor * textureColor.rgb;
            materialDiffuseColor = materialDiffuseColor * textureColor.rgb;
            materialEmissiveColor = materialEmissiveColor * textureColor.rgb;
            alpha = textureColor.a;
        }
        gl_FragColor = vec4(
            materialAmbientColor * ambientLightWeighting
            + materialDiffuseColor * diffuseLightWeighting
            + materialSpecularColor * specularLightWeighting
            + materialEmissiveColor,
            alpha
        );
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
    _uSampler = _gl.getUniformLocation(_shaderProgram, "uSampler");

    _uUseTextures = _gl.getUniformLocation(_shaderProgram, "uUseTextures");
    _uShowSpecularHighlights = _gl.getUniformLocation(_shaderProgram, "uShowSpecularHighlights");
    _uMaterialShininess = _gl.getUniformLocation(_shaderProgram, "uMaterialShininess");
    _uPointLightingLocation = _gl.getUniformLocation(_shaderProgram, "uPointLightingLocation");
    _uPointLightingSpecularColor = _gl.getUniformLocation(_shaderProgram, "uPointLightingSpecularColor");
    _uPointLightingDiffuseColor = _gl.getUniformLocation(_shaderProgram, "uPointLightingDiffuseColor");
    _uMaterialAmbientColor = _gl.getUniformLocation(_shaderProgram, "uMaterialAmbientColor");
    _uMaterialDiffuseColor = _gl.getUniformLocation(_shaderProgram, "uMaterialDiffuseColor");
    _uMaterialSpecularColor = _gl.getUniformLocation(_shaderProgram, "uMaterialSpecularColor");
    _uMaterialEmissiveColor = _gl.getUniformLocation(_shaderProgram, "uMaterialEmissiveColor");
    _uAmbientLightingColor = _gl.getUniformLocation(_shaderProgram, "uAmbientLightingColor");
  }


  void _initTextures() {
    _moonTexture = _gl.createTexture();
    ImageElement moonImage = new Element.tag('img');
    moonImage.onLoad.listen((e) {
      _handleLoadedTexture(_moonTexture, moonImage);
    });
    moonImage.src = "./moon.gif";

    _crateTexture = _gl.createTexture();
    ImageElement crateImage = new Element.tag('img');
    crateImage.onLoad.listen((e) {
      _handleLoadedTexture(_crateTexture, crateImage);
    });
    crateImage.src = "./crate.gif";
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

  void _initTextureFramebuffer() {
    _rttFramebuffer = _gl.createFramebuffer();
    _gl.bindFramebuffer(webgl.RenderingContext.FRAMEBUFFER, _rttFramebuffer);

    _rttTexture = _gl.createTexture();
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _rttTexture);
    _gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MAG_FILTER, webgl.RenderingContext.LINEAR);
    _gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MIN_FILTER, webgl.RenderingContext.LINEAR_MIPMAP_NEAREST);
    _gl.generateMipmap(webgl.RenderingContext.TEXTURE_2D);

    _gl.texImage2D(webgl.RenderingContext.TEXTURE_2D, 0, webgl.RenderingContext.RGBA, 512, 512, 0, webgl.RenderingContext.RGBA, webgl.RenderingContext.UNSIGNED_BYTE, null);

    webgl.Renderbuffer renderbuffer = _gl.createRenderbuffer();
    _gl.bindRenderbuffer(webgl.RenderingContext.RENDERBUFFER, renderbuffer);
    _gl.renderbufferStorage(webgl.RenderingContext.RENDERBUFFER, webgl.RenderingContext.DEPTH_COMPONENT16, 512, 512);

    _gl.framebufferTexture2D(webgl.RenderingContext.FRAMEBUFFER, webgl.RenderingContext.COLOR_ATTACHMENT0, webgl.RenderingContext.TEXTURE_2D, _rttTexture, 0);
    _gl.framebufferRenderbuffer(webgl.RenderingContext.FRAMEBUFFER, webgl.RenderingContext.DEPTH_ATTACHMENT, webgl.RenderingContext.RENDERBUFFER, renderbuffer);

    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, null);
    _gl.bindRenderbuffer(webgl.RenderingContext.RENDERBUFFER, null);
    _gl.bindFramebuffer(webgl.RenderingContext.FRAMEBUFFER, null);
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
    List<double> textureCoords = [
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


    _laptopScreenVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopScreenVertexPositionBuffer);
    vertices = [
        0.580687, 0.659, 0.813106,
        -0.580687, 0.659, 0.813107,
        0.580687, 0.472, 0.113121,
        -0.580687, 0.472, 0.113121,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertices), webgl.RenderingContext.STATIC_DRAW);

    _laptopScreenVertexNormalBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopScreenVertexNormalBuffer);
    vertexNormals = [
        0.000000, -0.965926, 0.258819,
        0.000000, -0.965926, 0.258819,
        0.000000, -0.965926, 0.258819,
        0.000000, -0.965926, 0.258819,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertexNormals), webgl.RenderingContext.STATIC_DRAW);

    _laptopScreenVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopScreenVertexTextureCoordBuffer);
    textureCoords = [
        1.0, 1.0,
        0.0, 1.0,
        1.0, 0.0,
        0.0, 0.0,
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(textureCoords), webgl.RenderingContext.STATIC_DRAW);
  }

  void _handleLoadedLaptop(Map laptopData) {
    // NOTE: The JSON library decodes into a List<num> which contains a mix of int and double types wherever possible
    //       without losing precision. Float32List.fromList() is picky and throws an error instead of doing a simple
    //       downcast. Therefore, we need to convert the list, which is what map(...) does.

    _laptopVertexNormalBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopVertexNormalBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(laptopData["vertexNormals"].map((x) => x.toDouble()).toList()), webgl.RenderingContext.STATIC_DRAW);

    _laptopVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopVertexTextureCoordBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(laptopData["vertexTextureCoords"].map((x) => x.toDouble()).toList()), webgl.RenderingContext.STATIC_DRAW);

    _laptopVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopVertexPositionBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(laptopData["vertexPositions"].map((x) => x.toDouble()).toList()), webgl.RenderingContext.STATIC_DRAW);

    _laptopVertexIndexBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _laptopVertexIndexBuffer);
    _gl.bufferData(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(laptopData["indices"]), webgl.RenderingContext.STATIC_DRAW);
    _laptopVertexCount = laptopData["indices"].length;
  }

  void _loadLaptop() {
    // Dart makes this way easier compared to JS <3
    HttpRequest.getString("macbook.json")
    .then( (String response) {
      _handleLoadedLaptop(JSON.decode(response));
    })
    .catchError((Error e) {
      print(e.toString());
    });
  }

  void _drawSceneOnLaptopScreen() {
    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);

    // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
    _pMatrix = makePerspectiveMatrix(radians(45.0), _laptopScreenAspectRatio, 0.1, 100.0);

    _gl.uniform1i(_uShowSpecularHighlights, 0); //false
    _gl.uniform3f(_uAmbientLightingColor, 0.2, 0.2, 0.2);
    _gl.uniform3f(_uPointLightingLocation, 0, 0, -5);
    _gl.uniform3f(_uPointLightingDiffuseColor, 0.8, 0.8, 0.8);

    _gl.uniform1i(_uShowSpecularHighlights, 0); //false
    _gl.uniform1i(_uUseTextures, 1); //true

    _gl.uniform3f(_uMaterialAmbientColor, 1.0, 1.0, 1.0);
    _gl.uniform3f(_uMaterialDiffuseColor, 1.0, 1.0, 1.0);
    _gl.uniform3f(_uMaterialSpecularColor, 0.0, 0.0, 0.0);
    _gl.uniform1f(_uMaterialShininess, 0);
    _gl.uniform3f(_uMaterialEmissiveColor, 0.0, 0.0, 0.0);
    
    _mvMatrix = new Matrix4.identity();
    _mvMatrix.translate(0.0, 0.0, -5.0);
    _mvMatrix.rotate(new Vector3(1.0, 0.0, 0.0), radians(30.0));

    _mvPushMatrix();
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(_moonAngle));
    _mvMatrix.translate(2.0, 0.0, 0.0);
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
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(_cubeAngle));
    _mvMatrix.translate(1.25, 0.0, 0.0);
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexNormalBuffer);
    _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _cubeVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _crateTexture);
    _gl.uniform1i(_uSampler, 0);

    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _cubeVertexIndexBuffer);
    _setMatrixUniforms();
    _gl.drawElements(webgl.RenderingContext.TRIANGLES, _cubeVertexCount, webgl.RenderingContext.UNSIGNED_SHORT, 0);

    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _rttTexture);
    _gl.generateMipmap(webgl.RenderingContext.TEXTURE_2D);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, null);
  }


  void drawScene(double time) {
    _gl.bindFramebuffer(webgl.RenderingContext.FRAMEBUFFER, _rttFramebuffer);
    _drawSceneOnLaptopScreen();

    _gl.bindFramebuffer(webgl.RenderingContext.FRAMEBUFFER, null);

    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);

    // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
    _pMatrix = makePerspectiveMatrix(radians(45.0), _viewportWidth / _viewportHeight, 0.1, 100.0);

    _mvMatrix = new Matrix4.identity();

    _mvPushMatrix();

    _mvMatrix.translate(0.0, -0.4, -2.2);
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(_laptopAngle));
    _mvMatrix.rotate(new Vector3(1.0, 0.0, 0.0), radians(-90.0));

    _gl.uniform1i(_uShowSpecularHighlights, 1); //true
    _gl.uniform3f(_uPointLightingLocation, -1, 2, -1);

    _gl.uniform3f(_uAmbientLightingColor, 0.2, 0.2, 0.2);
    _gl.uniform3f(_uPointLightingDiffuseColor, 0.8, 0.8, 0.8);
    _gl.uniform3f(_uPointLightingSpecularColor, 0.8, 0.8, 0.8);

    // The laptop body is quite shiny and has no texture.  It reflects lots of specular light
    _gl.uniform3f(_uMaterialAmbientColor, 1.0, 1.0, 1.0);
    _gl.uniform3f(_uMaterialDiffuseColor, 1.0, 1.0, 1.0);
    _gl.uniform3f(_uMaterialSpecularColor, 1.5, 1.5, 1.5);
    _gl.uniform1f(_uMaterialShininess, 5.0);
    _gl.uniform3f(_uMaterialEmissiveColor, 0.0, 0.0, 0.0);
    _gl.uniform1i(_uUseTextures, 0); //false

    if (_laptopVertexPositionBuffer != null) {
      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopVertexPositionBuffer);
      _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopVertexTextureCoordBuffer);
      _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopVertexNormalBuffer);
      _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

      _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _laptopVertexIndexBuffer);
      _setMatrixUniforms();
      _gl.drawElements(webgl.RenderingContext.TRIANGLES, _laptopVertexCount, webgl.RenderingContext.UNSIGNED_SHORT, 0);
    }

    _gl.uniform3f(_uMaterialAmbientColor, 0.0, 0.0, 0.0);
    _gl.uniform3f(_uMaterialDiffuseColor, 0.0, 0.0, 0.0);
    _gl.uniform3f(_uMaterialSpecularColor, 0.5, 0.5, 0.5);
    _gl.uniform1f(_uMaterialShininess, 20.0);
    _gl.uniform3f(_uMaterialEmissiveColor, 1.5, 1.5, 1.5);
    _gl.uniform1i(_uUseTextures, 1); //true

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopScreenVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopScreenVertexNormalBuffer);
    _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _laptopScreenVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _rttTexture);
    _gl.uniform1i(_uSampler, 0);

    _setMatrixUniforms();
    _gl.drawArrays(webgl.RenderingContext.TRIANGLE_STRIP, 0, 4);

    _mvPopMatrix();

    _animate(time);

    // keep drawing
    window.requestAnimationFrame(this.drawScene);
  }

  void _animate(double timeNow) {
    if (_lastTime != 0) {
      double elapsed = timeNow - _lastTime;

      _moonAngle += 0.05 * elapsed;
      _cubeAngle += 0.05 * elapsed;
      _laptopAngle -= 0.005 * elapsed;
    }
    _lastTime = timeNow;
  }


  void start() {
    window.requestAnimationFrame(this.drawScene);
  }

}


void main() {
  Lesson16 lesson = new Lesson16(document.querySelector('#drawHere'));
  lesson.start();
}
