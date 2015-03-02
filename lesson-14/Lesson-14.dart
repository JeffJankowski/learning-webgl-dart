library lesson14;

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
class Lesson14 {

  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;

  webgl.Texture _earthTexture, _galvanizedTexture;

  webgl.Buffer _teapotVertexTextureCoordBuffer;
  webgl.Buffer _teapotVertexPositionBuffer;
  webgl.Buffer _teapotVertexNormalBuffer;
  webgl.Buffer _teapotVertexIndexBuffer;

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
  webgl.UniformLocation _uUseLighting;
  webgl.UniformLocation _uUseTextures;
  webgl.UniformLocation _uShowSpecularHighlights;
  webgl.UniformLocation _uAmbientColor;
  webgl.UniformLocation _uPointLightingLocation;
  webgl.UniformLocation _uPointLightingSpecularColor;
  webgl.UniformLocation _uPointLightingDiffuseColor;
  webgl.UniformLocation _uMaterialShininess;

  InputElement _elmLighting, _elmSpecular;
  SelectElement _elmTexture;
  InputElement _elmAmbientR, _elmAmbientG, _elmAmbientB;
  InputElement _elmLightPositionX, _elmLightPositionY, _elmLightPositionZ;
  InputElement _elmDiffuseR, _elmDiffuseG, _elmDiffuseB;
  InputElement _elmSpecularR, _elmSpecularG, _elmSpecularB;
  InputElement _elmShininess;

  double _lastTime = 0.0;
  double _teapotAngle = 180.0;
  int _teapotVertexCount = 0;

  Lesson14(CanvasElement canvas) {
    _viewportWidth = canvas.width;
    _viewportHeight = canvas.height;
    _gl = canvas.getContext("experimental-webgl");

    _mvMatrix = new Matrix4.identity();
    _mvMatrixStack = new Queue<Matrix4>();
    _pMatrix = new Matrix4.identity();

    _initShaders();
    _initTexture();
    _loadTeapot();

    _gl.clearColor(0.0, 0.0, 0.0, 1.0);
    _gl.enable(webgl.RenderingContext.DEPTH_TEST);

    _elmLighting = document.querySelector("#lighting");
    _elmSpecular = document.querySelector("#specular");
    _elmTexture = document.querySelector("#texture");
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
    _elmShininess = document.querySelector("#shininess");
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

    uniform float uMaterialShininess;

    uniform bool uShowSpecularHighlights;
    uniform bool uUseLighting;
    uniform bool uUseTextures;

    uniform vec3 uAmbientColor;

    uniform vec3 uPointLightingLocation;
    uniform vec3 uPointLightingSpecularColor;
    uniform vec3 uPointLightingDiffuseColor;

    uniform sampler2D uSampler;


    void main(void) {
        vec3 lightWeighting;
        if (!uUseLighting) {
            lightWeighting = vec3(1.0, 1.0, 1.0);
        } else {
            vec3 lightDirection = normalize(uPointLightingLocation - vPosition.xyz);
            vec3 normal = normalize(vTransformedNormal);

            float specularLightWeighting = 0.0;
            if (uShowSpecularHighlights) {
                vec3 eyeDirection = normalize(-vPosition.xyz);
                vec3 reflectionDirection = reflect(-lightDirection, normal);

                specularLightWeighting = pow(max(dot(reflectionDirection, eyeDirection), 0.0), uMaterialShininess);
            }

            float diffuseLightWeighting = max(dot(normal, lightDirection), 0.0);
            lightWeighting = uAmbientColor
                + uPointLightingSpecularColor * specularLightWeighting
                + uPointLightingDiffuseColor * diffuseLightWeighting;
        }

        vec4 fragmentColor;
        if (uUseTextures) {
            fragmentColor = texture2D(uSampler, vec2(vTextureCoord.s, vTextureCoord.t));
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

    // attach shaders to a webgl. program
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
    _uUseLighting = _gl.getUniformLocation(_shaderProgram, "uUseLighting");
    _uAmbientColor = _gl.getUniformLocation(_shaderProgram, "uAmbientColor");
    _uPointLightingLocation = _gl.getUniformLocation(_shaderProgram, "uPointLightingLocation");
    _uPointLightingSpecularColor = _gl.getUniformLocation(_shaderProgram, "uPointLightingSpecularColor");
    _uPointLightingDiffuseColor = _gl.getUniformLocation(_shaderProgram, "uPointLightingDiffuseColor");
    _uShowSpecularHighlights = _gl.getUniformLocation(_shaderProgram, "uShowSpecularHighlights");
    _uMaterialShininess = _gl.getUniformLocation(_shaderProgram, "uMaterialShininess");
  }


  void _initTexture() {
    _earthTexture = _gl.createTexture();
    ImageElement earthImage = new Element.tag('img');
    earthImage.onLoad.listen((e) {
      _handleLoadedTexture(_earthTexture, earthImage);
    });
    earthImage.src = "./earth.jpg";

    _galvanizedTexture = _gl.createTexture();
    ImageElement metalImage = new Element.tag('img');
    metalImage.onLoad.listen((e) {
      _handleLoadedTexture(_galvanizedTexture, metalImage);
    });
    metalImage.src = "./arroway.de_metal+structure+06_d100_flat.jpg";
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

  void _handleLoadedTeapot(Map teapotData) {
    // NOTE: This is annoying.. I can't find a good way to force JSON decode into a list
    // of doubles instead of mixed with ints
    for (int i = 0; i < teapotData["vertexNormals"].length; i++)
      teapotData["vertexNormals"][i] *= 1.0;
    for (int i = 0; i < teapotData["vertexTextureCoords"].length; i++)
      teapotData["vertexTextureCoords"][i] *= 1.0;
    for (int i = 0; i < teapotData["vertexPositions"].length; i++)
      teapotData["vertexPositions"][i] *= 1.0;

    _teapotVertexNormalBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _teapotVertexNormalBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(teapotData["vertexNormals"]), webgl.RenderingContext.STATIC_DRAW);

    _teapotVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _teapotVertexTextureCoordBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(teapotData["vertexTextureCoords"]), webgl.RenderingContext.STATIC_DRAW);

    _teapotVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _teapotVertexPositionBuffer);
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(teapotData["vertexPositions"]), webgl.RenderingContext.STATIC_DRAW);

    _teapotVertexIndexBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _teapotVertexIndexBuffer);
    _gl.bufferData(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(teapotData["indices"]), webgl.RenderingContext.STATIC_DRAW);
    _teapotVertexCount = teapotData["indices"].length;

    document.getElementById("loadingtext").text = "";
  }

  void _loadTeapot() {
    // Dart makes this way easier compared to JS <3
    HttpRequest.getString("Teapot.json")
    .then( (String response) {
      _handleLoadedTeapot(JSON.decode(response));
    })
    .catchError((Error e) {
      print(e.toString());
    });
  }


  void render(double time) {
    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);

    if (_teapotVertexPositionBuffer != null && _teapotVertexNormalBuffer != null &&
    _teapotVertexTextureCoordBuffer != null && _teapotVertexIndexBuffer != null) {

      // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
      _pMatrix = makePerspectiveMatrix(radians(45.0), _viewportWidth / _viewportHeight, 0.1, 100.0);

      _gl.uniform1i(_uShowSpecularHighlights, _elmSpecular.checked ? 1 : 0);

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

      String texture = _elmTexture.value;
      _gl.uniform1i(_uUseTextures, texture != "none" ? 1 : 0);

      _mvMatrix = new Matrix4.identity();

      _mvMatrix.translate(0.0, 0.0, -40.0);
      _mvMatrix.rotate(new Vector3(1.0, 0.0, -1.0), _degToRad(23.4));
      _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), _degToRad(_teapotAngle));

      _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
      if (texture == "earth") {
        _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _earthTexture);
      } else if (texture == "galvanized") {
        _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _galvanizedTexture);
      }
      _gl.uniform1i(_uSampler, 0);

      _gl.uniform1f(_uMaterialShininess, double.parse(_elmShininess.value, (s) => 32.0));

      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _teapotVertexPositionBuffer);
      _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _teapotVertexTextureCoordBuffer);
      _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

      _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _teapotVertexNormalBuffer);
      _gl.vertexAttribPointer(_aVertexNormal, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

      _gl.bindBuffer(webgl.RenderingContext.ELEMENT_ARRAY_BUFFER, _teapotVertexIndexBuffer);
      _setMatrixUniforms();
      _gl.drawElements(webgl.RenderingContext.TRIANGLES, _teapotVertexCount, webgl.RenderingContext.UNSIGNED_SHORT, 0);

      _animate(time);
    }

    // keep drawing
    window.requestAnimationFrame(this.render);
  }

  void _animate(double timeNow) {
    if (_lastTime != 0) {
      double elapsed = timeNow - _lastTime;

      _teapotAngle += 0.05 * elapsed;
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
  Lesson14 lesson = new Lesson14(document.querySelector('#drawHere'));
  lesson.start();
}
