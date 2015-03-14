library lesson9;

import 'dart:html';
import 'package:vector_math/vector_math.dart';
import 'dart:collection';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:math' as math;


/**
 * based on:
 * http://learningwebgl.com/blog/?p=1008
 *
 * NOTE: Need to run from web server when using Chrome due to cross-site security issues loading texture images.
 *       Running from Firefox or Dartium's local server will work as well.
 */
class Lesson09 {

  webgl.RenderingContext _gl;
  webgl.Program _shaderProgram;
  int _viewportWidth, _viewportHeight;

  webgl.Texture _texture;

  webgl.Buffer _starVertexTextureCoordBuffer;
  webgl.Buffer _starVertexPositionBuffer;

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

  InputElement _elmTwinkle;

  double _zoom = -15.0, _tilt = 90.0, _spin = 0.0;

  double _lastTime = 0.0;
  List<bool> _currentlyPressedKeys;

  List<Star> _stars;
  static const int STARS = 50;

  Lesson09(CanvasElement canvas) {
    // weird, but without specifying size this array throws exception on []
    _currentlyPressedKeys = new List<bool>(128);
    _viewportWidth = canvas.width;
    _viewportHeight = canvas.height;
    _gl = canvas.getContext("experimental-webgl");

    _mvMatrix = new Matrix4.identity();
    _mvMatrixStack = new Queue<Matrix4>();
    _pMatrix = new Matrix4.identity();

    _initShaders();
    _initBuffers();
    _initTexture();
    _initWorldObjects();

    _gl.clearColor(0.0, 0.0, 0.0, 1.0);
    //disable DEPTH_TEST for blending
    //_gl.enable(webgl.RenderingContext.DEPTH_TEST);

    document.onKeyDown.listen(this._handleKeyDown);
    document.onKeyUp.listen(this._handleKeyUp);

    _elmTwinkle = document.querySelector("#twinkle");
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

    uniform vec3 uColor;

    void main(void) {
        vec4 textureColor = texture2D(uSampler, vec2(vTextureCoord.s, vTextureCoord.t));
        gl_FragColor = textureColor * vec4(uColor, 1.0);
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

  void _initBuffers() {

    // create star
    _starVertexPositionBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _starVertexPositionBuffer);
    List<double> vertices = [
        -1.0, -1.0,  0.0,
        1.0, -1.0,  0.0,
        -1.0,  1.0,  0.0,
        1.0,  1.0,  0.0
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(vertices), webgl.RenderingContext.STATIC_DRAW);

    _starVertexTextureCoordBuffer = _gl.createBuffer();
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _starVertexTextureCoordBuffer);
    List<double> textureCoords = [
        0.0, 0.0,
        1.0, 0.0,
        0.0, 1.0,
        1.0, 1.0
    ];
    _gl.bufferData(webgl.RenderingContext.ARRAY_BUFFER, new Float32List.fromList(textureCoords), webgl.RenderingContext.STATIC_DRAW);
  }

  void _initTexture() {
    _texture = _gl.createTexture();
    ImageElement image = new Element.tag('img');
    image.onLoad.listen((e) {
      _handleLoadedTexture(_texture, image);
    });
    image.src = "./star.gif";
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
    // No need for Mipmap
    //_gl.texParameteri(webgl.RenderingContext.TEXTURE_2D, webgl.RenderingContext.TEXTURE_MIN_FILTER, webgl.RenderingContext.LINEAR_MIPMAP_NEAREST);
    //_gl.generateMipmap(webgl.RenderingContext.TEXTURE_2D);

    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, null);
  }

  void _setMatrixUniforms() {
    _gl.uniformMatrix4fv(_uPMatrix, false, _pMatrix.storage);
    _gl.uniformMatrix4fv(_uMVMatrix, false, _mvMatrix.storage);
  }

  void drawScene(double time) {
    _gl.viewport(0, 0, _viewportWidth, _viewportHeight);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | webgl.RenderingContext.DEPTH_BUFFER_BIT);

    // field of view is 45°, width-to-height ratio, hide things closer than 0.1 or further than 100
    _pMatrix = makePerspectiveMatrix(radians(45.0), _viewportWidth / _viewportHeight, 0.1, 100.0);

    _gl.blendFunc(webgl.RenderingContext.SRC_ALPHA, webgl.RenderingContext.ONE);
    _gl.enable(webgl.RenderingContext.BLEND);

    _mvMatrix = new Matrix4.identity();
    _mvMatrix.translate(new Vector3(0.0, 0.0, _zoom));
    _mvMatrix.rotate(new Vector3(1.0, 0.0, 0.0), radians(_tilt));

    // transform/draw each star
    for (Star s in _stars) {
      _drawSceneStar(s);
      _spin += 0.1;
    }

    // rotate
    _animate(time);
    _handleKeys();

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

      for(Star s in _stars) {
        s.animate(elapsed);
      }
    }
    _lastTime = timeNow;
  }

  void _handleKeys() {
    if (_currentlyPressedKeys.elementAt(33) != null && _currentlyPressedKeys.elementAt(33)) {
      // Page Up
      _zoom -= 0.1;
    }
    if (_currentlyPressedKeys.elementAt(34) != null && _currentlyPressedKeys.elementAt(34)) {
      // Page Down
      _zoom += 0.1;
    }
    if (_currentlyPressedKeys.elementAt(38) != null && _currentlyPressedKeys.elementAt(38)) {
      // Up cursor key
      _tilt += 2.0;
    }
    if (_currentlyPressedKeys.elementAt(40) != null && _currentlyPressedKeys.elementAt(40)) {
      // Down cursor key
      _tilt -= 2.0;
    }
  }

  void start() {
    window.requestAnimationFrame(this.drawScene);
  }

  void _initWorldObjects() {
    _stars = new List<Star>();

    for (int i = 0; i < STARS; i++) {
      _stars.add(new Star((i / STARS) * 5, i / STARS));
    }
  }

  // replacement method for Star.prototype.draw in JS version
  void _drawSceneStar(Star star) {
    _mvPushMatrix();

    // Move to the star's position
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(star.angle));
    _mvMatrix.translate(new Vector3(star.dist, 0.0, 0.0));

    // Rotate back so that the star is facing the viewer
    _mvMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(-star.angle));
    _mvMatrix.rotate(new Vector3(1.0, 0.0, 0.0), radians(-_tilt));

    if (_elmTwinkle.checked) {
      // Draw a non-rotating star in the alternate "twinkling" color
      _gl.uniform3f(_uColor, star.twinkleR, star.twinkleG, star.twinkleB);
      _drawStar();
    }

    // All stars spin around the Z axis at the same rate
    _mvMatrix.rotate(new Vector3(0.0, 0.0, 1.0), radians(_spin));

    // Draw the star in its main color
    _gl.uniform3f(_uColor, star.r, star.g, star.b);
    _drawStar();

    _mvPopMatrix();
  }

  void _drawStar() {
    _gl.activeTexture(webgl.RenderingContext.TEXTURE0);
    _gl.bindTexture(webgl.RenderingContext.TEXTURE_2D, _texture);
    _gl.uniform1i(_uSampler, 0);

    // texture
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _starVertexTextureCoordBuffer);
    _gl.vertexAttribPointer(_aTextureCoord, 2, webgl.RenderingContext.FLOAT, false, 0, 0);

    // vertices
    _gl.bindBuffer(webgl.RenderingContext.ARRAY_BUFFER, _starVertexPositionBuffer);
    _gl.vertexAttribPointer(_aVertexPosition, 3, webgl.RenderingContext.FLOAT, false, 0, 0);

    _setMatrixUniforms();
    _gl.drawArrays(webgl.RenderingContext.TRIANGLE_STRIP, 0, 4);
  }
}

class Star {
  double angle = 0.0;
  double dist, rotationSpeed;
  double r, g, b;
  double twinkleR, twinkleG, twinkleB;

  math.Random rand;

  static const double EFFECT_FPMS = 60 / 1000;

  Star(double startingDist, double rotationSpeed) {
    dist = startingDist;
    this.rotationSpeed = rotationSpeed;

    rand = new math.Random();

    randomizeColors();
  }

  void randomizeColors() {
    // Give the star a random color for normal
    // circumstances...
    r = rand.nextDouble();
    g = rand.nextDouble();
    b = rand.nextDouble();

    // When the star is twinkling, we draw it twice, once
    // in the color below (not spinning) and then once in the
    // main color defined above.
    twinkleR = rand.nextDouble();
    twinkleG = rand.nextDouble();
    twinkleB = rand.nextDouble();
  }

  void animate(double elapsedTime) {
    angle += rotationSpeed * EFFECT_FPMS * elapsedTime;

    // Decrease the distance, resetting the star to the outside of
    // the spiral if it's at the center.
    dist -= 0.01 * EFFECT_FPMS * elapsedTime;
    if (dist < 0.0) {
      dist += 5.0;
      randomizeColors();
    }
  }
}

void main() {
  Lesson09 lesson = new Lesson09(document.querySelector('#drawHere'));
  lesson.start();
}
