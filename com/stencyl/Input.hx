package com.stencyl;

import com.stencyl.gestures.*;
import com.stencyl.Config;
import com.stencyl.utils.Log;
import com.stencyl.utils.Utils;

import openfl.events.Event;
#if desktop
import lime.ui.Joystick;
import lime.ui.JoystickHatPosition;
#end
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.events.TouchEvent;
import openfl.display.DisplayObject;
import openfl.geom.Point;
import openfl.ui.Multitouch;

#if (cpp || hl)
import openfl.sensors.Accelerometer;
#end

import openfl.ui.Keyboard;
import openfl.Lib;

using com.stencyl.event.EventDispatcher;

class Input
{
	//mouse state
	public static var mouseX:Float = 0;
	public static var mouseY:Float = 0;
	public static var mouseWheel:Bool;
	public static var mouseWheelDelta:Int = 0;
	
	public static var mouseDown:Bool;
	public static var mousePressed:Bool;
	public static var mouseReleased:Bool;
	public static var rightMouseDown:Bool;
	public static var rightMousePressed:Bool;
	public static var rightMouseReleased:Bool;
	public static var middleMouseDown:Bool;
	public static var middleMousePressed:Bool;
	public static var middleMouseReleased:Bool;
	
	//accelerometer state
	public static var accelX:Float;
	public static var accelY:Float;
	public static var accelZ:Float;
	
	//gestures state
	public static var multiTouchPoints:Map<String,TouchEvent>;
	public static var numTouches:Int;

	public static var swipedUp:Bool;
	public static var swipedDown:Bool;
	public static var swipedLeft:Bool;
	public static var swipedRight:Bool;
	
	public static var multipleGamepadsEnabled:Bool = false;
	
	//private
	
	private static var _enabled:Bool = false;
	
	//gestures state
	private static var _roxAgent:RoxGestureAgent;
	private static var _swipeDirection:Int;
	
	//joystick state
	#if desktop
	private static var _joySensitivity:Float = .12;
	private static var _joyState:Map<Int,JoystickState> = new Map<Int,JoystickState>();
	#end
	
	//keyboard state
	private static var _key:Array<Bool> = new Array<Bool>();
	
	//control state
	private static var _controlsToReset:Array<Control> = new Array<Control>();
	private static var _controlMap:Map<String,Control> = new Map<String,Control>();
	private static var _keyInput = new InputMethod<Int>(
		new Map<Int, Array<Control>>(),
		function(control) return control.keys);
	#if desktop
	private static var _joyInput = new InputMethod<String>(
		new Map<String, Array<Control>>(),
		function(control) return control.buttons);
	#end
	
	public static function resetStatics():Void
	{
		//global effects

		Engine.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		Engine.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyUp);
		Engine.stage.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
		Engine.stage.removeEventListener(MouseEvent.MOUSE_UP, onMouseUp);
		#if !mobile
		Engine.stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);
		Engine.stage.removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
		Engine.stage.removeEventListener(MouseEvent.RIGHT_MOUSE_UP, onRightMouseUp);
		Engine.stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown);
		Engine.stage.removeEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp);
		#end

		#if android
		Lib.current.stage.removeEventListener(KeyboardEvent.KEY_DOWN, ignoreBackKey);
		Lib.current.stage.removeEventListener(KeyboardEvent.KEY_UP, ignoreBackKey);
		#end
		
		if(Multitouch.supportsTouchEvents)
		{
			Engine.stage.removeEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
			Engine.stage.removeEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
			Engine.stage.removeEventListener(TouchEvent.TOUCH_END, onTouchEnd);
		}
		
		_roxAgent.detach();
		Engine.engine.root.removeEventListener(RoxGestureEvent.GESTURE_SWIPE, onSwipe);

		//statics

		mouseX = 0; mouseY = 0;
		mouseDown = mousePressed = mouseReleased = mouseWheel = false;
		rightMouseDown = rightMousePressed = rightMouseReleased = false;
		middleMouseDown = middleMousePressed = middleMouseReleased = false;
		mouseWheelDelta = 0;
		accelX = accelY = accelZ = 0;
		
		multiTouchPoints = null;
		numTouches = 0;
		_swipeDirection = 0;
		swipedUp = swipedDown = swipedRight = swipedLeft = false;
		_roxAgent = null;
		
		_enabled = false;
		_key = new Array<Bool>();
		
		#if desktop
		_joySensitivity = .12;
		_joyState = new Map<Int,JoystickState>();
		_joyInput.inputControlMap = new Map<String,Array<Control>>();
		#end
		_keyInput.inputControlMap = new Map<Int,Array<Control>>();

		_controlMap = new Map<String,Control>();
		_controlsToReset = new Array<Control>();
	}

	/**
	 * Defines a new input.
	 * @param	name		String to map the input to.
	 */
	public static function define(controlName:String, keyCodes:Array<Int>)
	{
		if(_controlMap.get(controlName) == null)
			_controlMap.set(controlName, new Control(controlName));
		else
			unmapControl(controlName);
		
		for(keyCode in keyCodes)
			addKeyToControl(keyCode, controlName);
	}
	
	public static function mapKey(keyCode:Int, controlName:String)
	{
		_keyInput.mapInputToControl(keyCode, _controlMap.get(controlName));
	}
	
	public static function unmapKey(keyCode:Int)
	{
		_keyInput.unmapInput(keyCode);
	}

	public static function addKeyToControl(keyCode:Int, controlName:String)
	{
		_keyInput.addInputToControl(keyCode, _controlMap.get(controlName));
	}

	public static function removeKeyFromControl(keyCode:Int, controlName:String)
	{
		_keyInput.removeInputFromControl(keyCode, _controlMap.get(controlName));
	}

	public static function getKeys(controlName:String):Array<Int>
	{
		return _keyInput.getInputsForControl(_controlMap.get(controlName));
	}
	
	public static function mapJoystickButton(id:String, controlName:String)
	{
		#if desktop
		_joyInput.mapInputToControl(JoystickButton.normalize(id), _controlMap.get(controlName));
		#end
	}
	
	public static function unmapJoystickButton(id:String)
	{
		#if desktop
		_joyInput.unmapInput(JoystickButton.normalize(id));
		#end
	}

	public static function addJoystickButtonToControl(id:String, controlName:String)
	{
		#if desktop
		_joyInput.addInputToControl(JoystickButton.normalize(id), _controlMap.get(controlName));
		#end
	}
	
	public static function removeJoystickButtonFromControl(id:String, controlName:String)
	{
		#if desktop
		_joyInput.removeInputFromControl(JoystickButton.normalize(id), _controlMap.get(controlName));
		#end
	}

	public static function getJoystickButtons(controlName:String):Array<String>
	{
		#if desktop
		return _joyInput.getInputsForControl(_controlMap.get(controlName));
		#end
		return null;
	}
	
	public static function unmapControl(controlName:String)
	{
		var control = _controlMap.get(controlName);
		
		_keyInput.removeAllInputsFromControl(control);

		#if desktop
		_joyInput.removeAllInputsFromControl(control);
		#end
	}
	
	public static function unmapKeyboardFromControl(controlName:String)
	{
		var control = _controlMap.get(controlName);
		_keyInput.removeAllInputsFromControl(control);
	}
	
	public static function unmapJoystickFromControl(controlName:String)
	{
		#if desktop
		var control = _controlMap.get(controlName);
		_joyInput.removeAllInputsFromControl(control);
		#end
	}
	
	public static function setJoySensitivity(val:Float)
	{
		#if desktop
		_joySensitivity = val;
		#end
	}

	public static function saveJoystickConfig(filename:String):Void
	{
		#if desktop
		var joyData = new Map<String, Dynamic>();
		joyData.set("_joyControlMap", [
			for (key in _joyInput.inputControlMap.keys())
				key => [
					for (control in _joyInput.inputControlMap.get(key))
					control.name
				]
			]);
		joyData.set("_joySensitivity", _joySensitivity);
		joyData.set("_format", 2);
		Utils.saveMap(joyData, "_jc-" + filename);
		#end
	}

	public static function loadJoystickConfig(filename:String):Void
	{
		#if desktop
		clearJoystickConfig();
		var joyData = new Map<String, Dynamic>();
		Utils.loadMap(joyData, "_jc-" + filename, function(success:Bool):Void
		{
			if (Utils.mapCount(joyData) > 0)
			{
				var format:Null<Int> = joyData.get("_format");
				if(format == null || format == 1)
				{
					var joyStringMap:Map<String,String> = joyData.get("_joyControlMap");
					for(k in joyStringMap.keys())
					{
						var controlName = joyStringMap.get(k);
						var control = _controlMap.get(controlName);
						
						k = JoystickButton.normalize(k);
						
						_joyInput.inputControlMap.set(k, [control]);
						
						control.buttons.push(k);
					}
				}
				else if(format == 2)
				{
					var joyStringMap:Map<String,Array<String>> = joyData.get("_joyControlMap");
					for(k in joyStringMap.keys())
					{
						var controlNames = joyStringMap.get(k);
						var controls = [for (controlName in controlNames) _controlMap.get(controlName)];
						
						k = JoystickButton.normalize(k);
						
						_joyInput.inputControlMap.set(k, controls);
						
						for(control in controls) control.buttons.push(k);
					}
				}
				_joySensitivity = joyData.get("_joySensitivity");
			}
		});
		#end
	}

	public static function clearJoystickConfig():Void
	{
		#if desktop
		for(control in _controlMap)
		{
			control.buttons = [];
		}
		_joyInput.inputControlMap = new Map<String,Array<Control>>();
		_joySensitivity = .12;
		#end
	}

	public static function loadInputConfig():Void
	{
		for(stencylControl in Config.keys.keys())
		{
			var value = Config.keys.get(stencylControl);
			var keyboardConstList = [for (keyname in value) Key.keyFromName(keyname)];
			
			var control = new Control(stencylControl);
			_controlMap.set(stencylControl, control);
			for(key in keyboardConstList)
			{
				_keyInput.addInputToControl(key, control);
			}
		}
	}

	/**
	 * If the input is held down.
	 * @param	input		An input name to check for.
	 * @return	True or false.
	 */
	public static function check(controlName:String):Bool
	{
		var control = _controlMap.get(controlName);
		
		return control != null && control.down;
	}

	/**
	 * If the input was pressed this frame.
	 * @param	input		An input name to check for.
	 * @return	True or false.
	 */
	public static function pressed(controlName:String):Bool
	{
		var control = _controlMap.get(controlName);
		
		return control != null && control.pressed;
	}

	/**
	 * If the input was released this frame.
	 * @param	input		An input name to check for.
	 * @return	True or false.
	 */
	public static function released(controlName:String):Bool
	{
		var control = _controlMap.get(controlName);
		
		return control != null && control.released;
	}
	
	public static function getButtonPressure(controlName:String):Float
	{
		var control = _controlMap.get(controlName);
		
		if(control != null)
		{
			return control.pressure;
		}
		
		return 0.0;
	}

	public static function simulateKeyPress(controlName:String)
	{
		controlPressed(_controlMap.get(controlName), 1.0);
	}
	
	public static function simulateKeyRelease(controlName:String)
	{
		controlReleased(_controlMap.get(controlName));
	}

	@:deprecated("Gamepads no longer need to be manually enabled.") public static function enableJoystick() {}

	public static function enable()
	{
		if(!_enabled && Engine.stage != null)
		{
			Engine.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown, false, 2);
			Engine.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp, false,  2);
			Engine.stage.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown, false, 2);
			Engine.stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp, false,  2);
			#if !mobile
			Engine.stage.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel, false, 2);
			Engine.stage.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown, false, 2);
			Engine.stage.addEventListener(MouseEvent.RIGHT_MOUSE_UP, onRightMouseUp, false, 2);
			Engine.stage.addEventListener(MouseEvent.MIDDLE_MOUSE_DOWN, onMiddleMouseDown, false, 2);
			Engine.stage.addEventListener(MouseEvent.MIDDLE_MOUSE_UP, onMiddleMouseUp, false, 2);
			#end

			//Disable default behavior for Android Back Button
			#if android
			if(Config.disableBackButton)
			{
				Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, ignoreBackKey);
				Lib.current.stage.addEventListener(KeyboardEvent.KEY_UP, ignoreBackKey);
			}
			#end
			
			if(Multitouch.supportsTouchEvents)
	        {
	        	multiTouchPoints = new Map<String,TouchEvent>();
	        	Multitouch.inputMode = openfl.ui.MultitouchInputMode.TOUCH_POINT;
	        	Engine.stage.addEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
	        	Engine.stage.addEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
         		Engine.stage.addEventListener(TouchEvent.TOUCH_END, onTouchEnd);
	        }
	        
	        #if desktop

			Joystick.onConnect.add(onJoystickConnected);

			for(joystick in Joystick.devices)
			{
				onJoystickConnected(joystick);
			}

			#end
	        
			_roxAgent = new RoxGestureAgent(Engine.engine.root, RoxGestureAgent.GESTURE);
			Engine.engine.root.addEventListener(RoxGestureEvent.GESTURE_SWIPE, onSwipe);
			
			_swipeDirection = -1;
			swipedLeft = false;
			swipedRight = false;
			swipedUp = false;
			swipedDown = false;
	        
	        mouseX = 0;
	        mouseY = 0;
	        accelX = 0;
	        accelY = 0;
	        accelZ = 0;
	        numTouches = 0;
	        _enabled = true;
		}
	}

	@:access(openfl.sensors.Accelerometer)
	public static function update()
	{
		swipedLeft = false;
		swipedRight = false;
		swipedUp = false;
		swipedDown = false;
		
		if(_swipeDirection > -1)
		{
			switch(_swipeDirection)
			{
				case 0:
					swipedLeft = true;
				case 1:
					swipedRight = true;
				case 2:
					swipedUp = true;
				case 3:
					swipedDown = true;
			}
			
			if(Engine.engine.whenSwiped != null)
				Engine.engine.whenSwiped.dispatch();
			
			_swipeDirection = -1;
		}
		
		#if (cpp || hl)
		if(Accelerometer.isSupported)
		{
			accelX = Accelerometer.currentX;
			accelY = Accelerometer.currentY;
			accelZ = Accelerometer.currentZ;
		}
		#end
		
		//Mouse is always in absolute coordinates, so adjust when screen size != game size
		mouseX = (Engine.stage.mouseX - Engine.screenOffsetX) / Engine.screenScaleX;
		mouseY = (Engine.stage.mouseY - Engine.screenOffsetY) / Engine.screenScaleY;
	
		var i = _controlsToReset.length;
		while(--i >= 0)
		{
			var control = _controlsToReset.pop();
			control.pressed = false;
			control.released = false;
		}
		
		if(mousePressed) mousePressed = false;
		if(mouseReleased) mouseReleased = false;
		if(rightMousePressed) rightMousePressed = false;
		if(rightMouseReleased) rightMouseReleased = false;
		if(middleMousePressed) middleMousePressed = false;
		if(middleMouseReleased) middleMouseReleased = false;
		
		mouseWheelDelta = 0;
	}

	#if android
	private static function ignoreBackKey(event:KeyboardEvent = null)
	{
		if(event.keyCode == lime.ui.KeyCode.APP_CONTROL_BACK)
		{
			event.preventDefault();

			var controls = _keyInput.inputControlMap.get(lime.ui.KeyCode.ESCAPE);
			
			if (event.type == KeyboardEvent.KEY_DOWN)
			{
				controlsPressed(controls, 1.0);
			}
			else
			{
				controlsReleased(controls);
			}
		}
	}
	#end
	
	private static function onSwipe(e:RoxGestureEvent):Void
	{
		var pt = cast(e.extra, Point);
        
        if(Math.abs(pt.x) <= Math.abs(pt.y))
        {
        	//Up
        	if(pt.y <= 0)
        	{
        		_swipeDirection = 2;
        	}
        	
        	//Down
        	else
        	{
        		_swipeDirection = 3;
        	}
        }
        
        else if(Math.abs(pt.x) > Math.abs(pt.y))
        {
        	//Left
        	if(pt.x <= 0)
        	{
        		_swipeDirection = 0;
        	}
        	
        	//Right
        	else
        	{
        		_swipeDirection = 1;
        	}
        }
	}

	private static inline function controlsPressed(controls:Array<Control>, pressure:Float)
	{
		if(controls != null)
			for(control in controls)
				controlPressed(control, pressure);
	}

	private static inline function controlsReleased(controls:Array<Control>)
	{
		if(controls != null)
			for(control in controls)
				controlReleased(control);
	}
	
	private static function controlPressed(control:Control, pressure:Float)
	{
		if(control == null) return;
		
		if(!control.down)
		{
			control.down = true;
			control.pressed = true;
			control.pressure = pressure;
			_controlsToReset.push(control);
			
			if(Engine.engine.keyPollOccurred)
			{
				//Due to order of execution, events will never get thrown since the
				//pressed/released flag is reset before the event checker sees it. So
				//throw the event immediately.
				var event = Engine.engine.whenKeyPressedEvents.getEvent(control.name);
				
				if(event != null)
				{
					event.dispatch(true, false);
				}
			}
		}
		else
			control.pressure = pressure;
	}
	
	private static function controlReleased(control:Control)
	{
		if(control == null) return;
		
		if(control.down)
		{
			control.down = false;
			control.released = true;
			control.pressure = 0.0;
			_controlsToReset.push(control);
			
			if(Engine.engine.keyPollOccurred)
			{
				//Due to order of execution, events will never get thrown since the
				//pressed/released flag is reset before the event checker sees it. So
				//throw the event immediately.
				var event = Engine.engine.whenKeyPressedEvents.getEvent(control.name);
				
				if(event != null)
				{
					event.dispatch(false, true);
				}
			}
		}
	}
	
	//This is called if a control may have changed it's state due to
	//it's key/button mappings changing.
	private static function controlStateUpdated(control:Control)
	{
		var pressure = 0.0;
		
		for(keyCode in control.keys)
		{
			if(_key[keyCode]) pressure = 1.0;
		}
		#if desktop
		for(buttonName in control.buttons)
		{
			var button = JoystickButton.fromID(buttonName);
			var device = button.a[JoystickButton.DEVICE];
			var controlType = button.a[JoystickButton.TYPE];
			var buttonID = button.a[2];
			
			if(!_joyState.exists(device))
				continue;
			
			var deviceState = _joyState.get(device);
			
			switch(controlType)
			{
				case JoystickButton.AXIS:
					if(deviceState.axisState[buttonID] == button.a[3])
						pressure = Math.max(pressure, Math.abs(deviceState.axisPressure[buttonID]));
				case JoystickButton.HAT:
					if(deviceState.hatState[buttonID] == button.a[3])
						pressure = 1.0;
				case JoystickButton.BUTTON:
					if(deviceState.buttonState[buttonID])
						pressure = 1.0;
			}
		}
		#end
		
		control.pressure = pressure;
		
		if(pressure > 0 && !control.down)
			controlPressed(control, pressure);
		else if(pressure == 0 && control.down)
			controlReleased(control);
	}

	private static function onKeyDown(e:KeyboardEvent = null)
	{
		var code:Int = e.keyCode;
		
		if (code > 7000)
		{
			return;
		}

		if(!_key[code])
		{
			_key[code] = true;
			controlsPressed(_keyInput.inputControlMap.get(code), 1.0);
		}
		
		Engine.engine.whenAnyKeyPressed.dispatch(e);
	}

	private static function onKeyUp(e:KeyboardEvent = null)
	{
		var code:Int = e.keyCode;
		
		if (code > 7000)
		{
			return;
		}
		
		if(_key[code])
		{
			_key[code] = false;
			controlsReleased(_keyInput.inputControlMap.get(code));
		}
		
		Engine.engine.whenAnyKeyReleased.dispatch(e);
	}

	private static function onMouseDown(e:MouseEvent)
	{
		//On mobile, mouse position isn't always updated till you touch, so we need to update immediately
		//so that events are properly notified
		#if (mobile || html5)
		mouseX = (Engine.stage.mouseX - Engine.screenOffsetX) / Engine.screenScaleX;
		mouseY = (Engine.stage.mouseY - Engine.screenOffsetY) / Engine.screenScaleY;
		#end
		
		if(!mouseDown)
		{
			mouseDown = true;
			mousePressed = true;
		}
	}

	private static function onMouseUp(e:MouseEvent)
	{
		//On mobile, mouse position isn't always updated till you touch, so we need to update immediately
		//so that events are properly notified
		#if (mobile || html5)
		mouseX = (Engine.stage.mouseX - Engine.screenOffsetX) / Engine.screenScaleX;
		mouseY = (Engine.stage.mouseY - Engine.screenOffsetY) / Engine.screenScaleY;
		#end
		
		mouseDown = false;
		mouseReleased = true;
	}

	private static function onRightMouseDown(e:MouseEvent)
	{
		if(!rightMouseDown)
		{
			rightMouseDown = true;
			rightMousePressed = true;
		}
	}
	
	private static function onRightMouseUp(e:MouseEvent)
	{
		rightMouseDown = false;
		rightMouseReleased = true;
	}
	
	private static function onMiddleMouseDown(e:MouseEvent)
	{
		if(!middleMouseDown)
		{
			middleMouseDown = true;
			middleMousePressed = true;
		}
	}
	
	private static function onMiddleMouseUp(e:MouseEvent)
	{
		middleMouseDown = false;
		middleMouseReleased = true;
	}
	
	private static function onMouseWheel(e:MouseEvent)
	{
		mouseWheel = true;
		mouseWheelDelta = e.delta;
	}
	
	#if desktop
	
	private static function onJoystickConnected(joystick:Joystick)
	{
		Log.info("Connected Joystick: " + joystick.name);
		
		var joystate = new JoystickState(joystick);
		_joyState.set(joystick.id, joystate);
		
		joystick.onAxisMove.add (function (axis:Int, value:Float) {
			onJoyAxisMove(joystate, axis, value);
		});

		joystick.onButtonDown.add (function (button:Int) {
			onJoyButtonDown(joystate, button);
		});

		joystick.onButtonUp.add (function (button:Int) {
			onJoyButtonUp(joystate, button);
		});

		joystick.onHatMove.add (function (hat:Int, position:JoystickHatPosition) {
			onJoyHatMove(joystate, hat, position);
		});

		joystick.onTrackballMove.add (function (trackball:Int, x:Float, y:Float) {
			onJoyBallMove(joystate, trackball, x, y);
		});

		joystick.onDisconnect.add (function () {
			Log.info("Disconnected Joystick: " + joystick.name);
			_joyState.remove(joystick.id);
		});
	}
	
	private static function onJoyAxisMove(joystate:JoystickState, axis:Int, value:Float)
	{
		var gpid = multipleGamepadsEnabled ? (joystate.joystick.id + ", ") : "";
		var oldState:Array<Int> = joystate.axisState;
		
		var cur:Int;
		var old:Int;

		if(value < -_joySensitivity)
			cur = -1;
		else if(value > _joySensitivity)
			cur = 1;
		else
			cur = 0;

		old = oldState[axis];

		if(cur != old)
		{
			if(old == -1)
				joyRelease(gpid + "-axis " + axis);
			else if(old == 1)
				joyRelease(gpid + "+axis " + axis);
			if(cur == -1)
				joyPress(gpid + "-axis " + axis, Math.abs(value));
			else if(cur == 1)
				joyPress(gpid + "+axis " + axis, Math.abs(value));
		}
		else if(cur != 0)
		{
			var controls = null;
			
			if(cur == -1)
				controls = _joyInput.inputControlMap.get(gpid + "-axis " + axis);
			else if(cur == 1)
				controls = _joyInput.inputControlMap.get(gpid + "+axis " + axis);
			
			if(controls != null) for(control in controls) control.pressure = Math.abs(value);
		}

		oldState[axis] = cur;

		joystate.axisPressure[axis] = value;
	}
	
	private static function onJoyBallMove(joystate:JoystickState, trackball:Int, x:Float, y:Float)
	{
		//not sure what to do with this
	}

	private static function onJoyHatMove(joystate:JoystickState, hat:Int, position:JoystickHatPosition)
	{
		var gpid = multipleGamepadsEnabled ? (joystate.joystick.id + ", ") : "";
		var oldX:Int = joystate.hatState[0];
		var oldY:Int = joystate.hatState[1];

		var newX:Int = position.left ? -1 : position.right ? 1 : 0;
		var newY:Int = position.up ? -1 : position.down ? 1 : 0;

		if(newX != oldX)
		{
			if(oldX == -1)
				joyRelease(gpid + "left hat");
			else if(oldX == 1)
				joyRelease(gpid + "right hat");
			if(newX == -1)
				joyPress(gpid + "left hat", 1.0);
			else if(newX == 1)
				joyPress(gpid + "right hat", 1.0);
		}
		if(newY != oldY)
		{
			if(oldY == -1)
				joyRelease(gpid + "up hat");
			else if(oldY == 1)
				joyRelease(gpid + "down hat");
			if(newY == -1)
				joyPress(gpid + "up hat", 1.0);
			else if(newY == 1)
				joyPress(gpid + "down hat", 1.0);
		}

		joystate.hatState = [newX, newY];
	}

	private static function onJoyButtonDown(joystate:JoystickState, button:Int)
	{
		var gpid = multipleGamepadsEnabled ? (joystate.joystick.id + ", ") : "";
		joystate.buttonState[button] = true;
		joyPress(gpid + button, 1.0);
	}

	private static function onJoyButtonUp(joystate:JoystickState, button:Int)
	{
		var gpid = multipleGamepadsEnabled ? (joystate.joystick.id + ", ") : "";
		joystate.buttonState[button] = false;
		joyRelease(gpid + button);
	}

	private static function joyPress(id:String, pressure:Float)
	{
		var controls = _joyInput.inputControlMap.get(id);
		controlsPressed(controls, pressure);
		
		Engine.engine.whenAnyGamepadPressed.dispatch(id);
	}

	private static function joyRelease(id:String)
	{
		controlsReleased(_joyInput.inputControlMap.get(id));

		Engine.engine.whenAnyGamepadReleased.dispatch(id);
	}
	#end

	private static function onTouchBegin(e:TouchEvent)
	{
		Engine.engine.whenMTStarted.dispatch(e);
	
		multiTouchPoints.set(Std.string(e.touchPointID), e);
		numTouches++;
	}
	
	private static function onTouchMove(e:TouchEvent)
	{
		Engine.engine.whenMTDragged.dispatch(e);
	
		multiTouchPoints.set(Std.string(e.touchPointID), e);
	}
	
	private static function onTouchEnd(e:TouchEvent)
	{
		Engine.engine.whenMTEnded.dispatch(e);
		
		multiTouchPoints.remove(Std.string(e.touchPointID));
		numTouches--;
	}
}

class Control
{
	public var name:String;
	public var keys:Array<Int>;
	#if desktop
	public var buttons:Array<String>;
	#end
	public var pressed:Bool;
	public var released:Bool;
	public var down:Bool;
	public var pressure:Float = 0;
	
	public function new(name:String)
	{
		this.name = name;
		keys = [];
		#if desktop
		buttons = [];
		#end
	}
}

@:access(com.stencyl.Input)
@:generic
class InputMethod<T>
{
	public var inputControlMap:Map<T,Array<Control>>;
	public var getInputs:(Control)->Array<T>;

	public function new(inputControlMap:Map<T,Array<Control>>, getInputs:Control->Array<T>)
	{
		this.inputControlMap = inputControlMap;
		this.getInputs = getInputs;
	}

	//map input to newControl alone, and no other control.
	public function mapInputToControl(input:T, newControl:Control)
	{
		if(!inputControlMap.exists(input))
			inputControlMap.set(input, []);
		var controlList = inputControlMap.get(input);

		for(control in controlList)
		{
			if(control != newControl)
			{
				getInputs(control).remove(input);
				Input.controlStateUpdated(control);
			}
		}
		
		if(getInputs(newControl).indexOf(input) == -1)
		{
			getInputs(newControl).push(input);
			controlList.push(newControl);
			Input.controlStateUpdated(newControl);
		}
	}
	
	//unmap input from any controls it may have been mapped to
	public function unmapInput(input:T)
	{
		var controlList = inputControlMap.get(input);
		if(controlList != null)
		{
			for(control in controlList)
			{
				getInputs(control).remove(input);
				Input.controlStateUpdated(control);
			}
		}
		
		inputControlMap.remove(input);
	}

	public function addInputToControl(input:T, control:Control)
	{
		if(getInputs(control).indexOf(input) == -1)
		{
			getInputs(control).push(input);
			Input.controlStateUpdated(control);
			
			if(!inputControlMap.exists(input))
				inputControlMap.set(input, []);
			inputControlMap.get(input).push(control);
		}
	}

	public function removeInputFromControl(input:T, control:Control)
	{
		if(getInputs(control).indexOf(input) != -1)
		{
			getInputs(control).remove(input);
			Input.controlStateUpdated(control);
			
			var controlList = inputControlMap.get(input);
			controlList.remove(control);
			if(controlList.length == 0)
				inputControlMap.remove(input);
		}
	}
	
	public function getInputsForControl(control:Control):Array<T>
	{
		if(control != null)
			return getInputs(control);
		
		return null;
	}

	public function removeAllInputsFromControl(control:Control)
	{
		var inputs = getInputs(control);
		while(inputs.length > 0)
		{
			var input = inputs.pop();
			var controls = inputControlMap.get(input);
			controls.remove(control);
			if(controls.length == 0)
				inputControlMap.remove(input);
		}
		
		Input.controlStateUpdated(control);
	}
}

#if desktop
class JoystickState
{
	public var joystick:Joystick;
	
	public var hatState:Array<Int>;
	public var axisState:Array<Int>;
	public var axisPressure:Array<Float>;
	public var buttonState:Array<Bool>;
	
	public function new(joystick:Joystick)
	{
		this.joystick = joystick;
		hatState = [0, 0];
		axisState = [for(i in 0...joystick.numAxes) 0];
		axisPressure = [for(i in 0...joystick.numAxes) 0.0];
		buttonState = [];
	}
}

class JoystickButton
{
	public static inline var DEVICE:Int = 0;
	public static inline var TYPE:Int = 1;

	public static inline var UP:Int = 0;
	public static inline var DOWN:Int = 1;
	public static inline var LEFT:Int = 2;
	public static inline var RIGHT:Int = 3;

	public static inline var AXIS:Int = 0;
	public static inline var HAT:Int = 1;
	public static inline var BUTTON:Int = 2;
	public static inline var BALL:Int = 3;
	
	private static var cacheFromID:Map<String, JoystickButton> = new Map<String, JoystickButton>();

	public static inline function normalize(id:String):String
	{
		if(!Input.multipleGamepadsEnabled && id.indexOf(", ") != -1)
		{
			return id.substring(id.indexOf(", ") + 2);
		}
		return id;
	}

	public static function fromID(id:String):JoystickButton
	{
		if(cacheFromID.exists(id))
			return cacheFromID.get(id);
		
		var b:JoystickButton = new JoystickButton();
		b.id = id;
		
		var device:Int = 0;
		if(Input.multipleGamepadsEnabled)
		{
			device = Std.parseInt(id.substr(0, id.indexOf(",")));
			id = id.substr(id.indexOf(",") + 2);
		}
		
		if(id.indexOf("axis") != -1)
		{
			var axis:Int = Std.parseInt(id.substr(id.lastIndexOf(" ") + 1));
			var sign:Int = id.charAt(0) == "+" ? 1 : -1;
			b.a = [device, AXIS, axis, sign];
		}
		else if(id.indexOf("hat") != -1)
		{
			var hat:Int = 0;
			var sign:Int = 0;
			switch(id.split(" ")[0])
			{
				case "up": hat = 1; sign = -1;
				case "down": hat = 1; sign = 1;
				case "right": hat = 0; sign = 1;
				case "left": hat = 0; sign = -1;
			}
			b.a = [device, HAT, hat, sign];
		}
		else
		{
			var button:Int = Std.parseInt(id);

			b.a = [device, BUTTON, button];
		}
		
		cacheFromID.set(b.id, b);
		return b;
	}

	public function new()
	{
		id = "";
		a = [];
	}

	public function equals(b:JoystickButton):Bool
	{
		return id == b.id;
	}

	public var id:String;
	public var a:Array<Int>;
}
#end
