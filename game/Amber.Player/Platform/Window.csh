// The window platform of Windows and Linux (C#: GameWindow with Silk.NET and the Amber OpenGL renderer): GLFW opens the
// window and collects the input, the frame of the software renderer is drawn with glDrawPixels (OpenGL 1.1, scaled with
// glPixelZoom). The loop is RunGame (Platform.csh); with an input script the real keyboard and mouse are ignored.

namespace Amber.Player.Platform;

using System;
using Amber.Base;
using Amber.Graphics;
using Amber.Player.Game;
using Amber.Player.Graphics;
using Glfw from "GLFW/glfw3.h";

extern "C" void glClearColor(float red, float green, float blue, float alpha);
extern "C" void glClear(uint32 mask);
extern "C" void glRasterPos2f(float x, float y);
extern "C" void glPixelZoom(float x, float y);
extern "C" void glPixelStorei(uint32 name, int value);
extern "C" void glDrawPixels(int width, int height, uint32 format, uint32 type, void* pixels);
extern "C" void glViewport(int x, int y, int width, int height);
extern "C" void glReadPixels(int x, int y, int width, int height, uint32 format, uint32 type, void* pixels);
extern "C" void glReadBuffer(uint32 mode);

const uint32 GlColorBufferBit = 0x4000;
const uint32 GlRgba = 0x1908;
const uint32 GlUnsignedByte = 0x1401;
const uint32 GlUnpackAlignment = 0x0CF5;
const uint32 GlPackAlignment = 0x0D05;
const uint32 GlBack = 0x0405;

/// The input of the window (the callbacks of GLFW have no user data in this program).
InputState WindowInput = InputState.Create();

/// True while an input script drives the game: the real keyboard and mouse are ignored.
bool WindowScripted = false;

int WindowWidth = 320;
int WindowHeight = 200;

void OnGlfwError(int code, char* description)
{
	unsafe
	{
		Console.WriteErrorLine("GLFW error " + code + ": " + string.FromCStr(description));
	}
}

void OnKey(Glfw.GLFWwindow* window, int key, int scancode, int action, int mods)
{
	if (WindowScripted || key <= 0)
		return;

	if (action == Glfw.GLFW_PRESS)
		WindowInput.KeyDown((Key)key);
	else if (action == Glfw.GLFW_RELEASE)
		WindowInput.KeyUp((Key)key);
}

void OnChar(Glfw.GLFWwindow* window, uint32 codePoint)
{
	if (!WindowScripted)
		WindowInput.CharTyped(CodePointText((int)codePoint));
}

void OnCursor(Glfw.GLFWwindow* window, double x, double y)
{
	// window coordinates -> virtual screen
	if (!WindowScripted)
		WindowInput.MouseMoved((int)(x * (double)VirtualScreenWidth / (double)WindowWidth), (int)(y * (double)VirtualScreenHeight / (double)WindowHeight));
}

void OnMouseButton(Glfw.GLFWwindow* window, int button, int action, int mods)
{
	if (WindowScripted || button > 2)
		return;

	if (action == Glfw.GLFW_PRESS)
		WindowInput.MouseButtonDown((MouseButton)button);
	else if (action == Glfw.GLFW_RELEASE)
		WindowInput.MouseButtonUp((MouseButton)button);
}

void OnScroll(Glfw.GLFWwindow* window, double x, double y)
{
	if (!WindowScripted)
		WindowInput.MouseWheel((float)y);
}

/// Runs the game in a window until it quits or the window is closed. Returns the exit code.
Error<int> RunWindow(AnyGame game, LaunchOptions options)
{
	Optional<InputScript> script = null;

	if (options.Script != null)
		script = try InputScript.Load(options.Script);

	WindowScripted = script is InputScript;
	WindowWidth = VirtualScreenWidth * options.Scale;
	WindowHeight = VirtualScreenHeight * options.Scale;

	Glfw.glfwSetErrorCallback(OnGlfwError);

	if (Glfw.glfwInit() == 0)
		return error("GLFW could not be initialized (no display?). Use --headless --script <file> to run without a window.", (int)ErrorKind.InvalidOperation);

	Glfw.glfwWindowHint(Glfw.GLFW_RESIZABLE, 0);

	Glfw.GLFWwindow* window = null;

	if (options.Editor)
		window = Glfw.glfwCreateWindow(WindowWidth, WindowHeight, "Amber map editor", null, null);
	else
		window = Glfw.glfwCreateWindow(WindowWidth, WindowHeight, "Amber Player", null, null);

	if (window == null)
	{
		Glfw.glfwTerminate();

		return error("The window could not be created.", (int)ErrorKind.InvalidOperation);
	}

	Glfw.glfwMakeContextCurrent(window);
	Glfw.glfwSwapInterval(1);
	Glfw.glfwSetKeyCallback(window, OnKey);
	Glfw.glfwSetCharCallback(window, OnChar);
	Glfw.glfwSetCursorPosCallback(window, OnCursor);
	Glfw.glfwSetMouseButtonCallback(window, OnMouseButton);
	Glfw.glfwSetScrollCallback(window, OnScroll);

	var platform = GlfwPlatform { Window = window, Scale = options.Scale };
	var result = RunGame(ref platform, game, script);

	Glfw.glfwDestroyWindow(window);
	Glfw.glfwTerminate();

	return result;
}

/// A GLFW window with the software renderer.
struct GlfwPlatform : IPlatform
{
	Glfw.GLFWwindow* Window;
	int Scale;

	InputState Input()
	{
		return WindowInput;
	}

	bool IsOpen()
	{
		return Glfw.glfwWindowShouldClose(Window) == 0;
	}

	void Poll()
	{
		Glfw.glfwPollEvents();
	}

	double Seconds()
	{
		return Glfw.glfwGetTime();
	}

	bool ShowsFrames()
	{
		return true;
	}

	void Present(DrawList list)
	{
		PresentFrame(RenderList(list, VirtualScreenWidth, VirtualScreenHeight), Scale);
	}

	Error<void> Screenshot(string path)
	{
		return SaveWindowScreenshot(path);
	}

	void EndFrame()
	{
		Glfw.glfwSwapBuffers(Window);
	}
}

/// Draws the frame scaled into the window (rows are flipped by the negative zoom: the frame starts at the top).
void PresentFrame(Image frame, int scale)
{
	glViewport(0, 0, WindowWidth, WindowHeight);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GlColorBufferBit);
	glPixelStorei(GlUnpackAlignment, 1);
	glRasterPos2f(-1.0f, 1.0f);
	glPixelZoom((float)scale, (float)(-scale));

	unsafe
	{
		glDrawPixels(frame.Width, frame.Height, GlRgba, GlUnsignedByte, (void*)&frame.Data[0]);
	}
}

/// Reads the back buffer of the window and writes it as a PNG (C#: GameWindow.SaveScreenshot).
Error<void> SaveWindowScreenshot(string path)
{
	var pixels = Image.Create(WindowWidth, WindowHeight);

	glReadBuffer(GlBack);
	glPixelStorei(GlPackAlignment, 1);

	unsafe
	{
		glReadPixels(0, 0, WindowWidth, WindowHeight, GlRgba, GlUnsignedByte, (void*)&pixels.Data[0]);
	}

	// OpenGL rows start at the bottom
	var flipped = Image.Create(WindowWidth, WindowHeight);
	int stride = WindowWidth * 4;

	for (var y = 0; y < WindowHeight; y += 1)
	{
		for (var i = 0; i < stride; i += 1)
			flipped.Data[y * stride + i] = pixels.Data[(WindowHeight - 1 - y) * stride + i];
	}

	for (var i = 3; i < flipped.Data.Length; i += 4)
		flipped.Data[i] = 255;

	return SaveScreenshot(flipped, path, 1);
}
