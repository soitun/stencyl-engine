package com.stencyl.models;

import polygonal.ds.IntHashTable;

import openfl.display.BlendMode;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.DisplayObjectShader;
#if !(flash || canvas)
import openfl.display.Shader;
#end
import openfl.display.Sprite;
import openfl.display.Tile;
import openfl.display.TileContainer;
import openfl.display.Tilemap;
import openfl.display.Tileset;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.display.Graphics;
import openfl.filters.BitmapFilter;
import openfl.filters.ColorMatrixFilter;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.geom.Transform;
import openfl.utils.ByteArray;

import com.stencyl.Config;
import com.stencyl.Input;
import com.stencyl.Engine;

import com.stencyl.graphics.AbstractAnimation;
import com.stencyl.graphics.BitmapAnimation;
import com.stencyl.graphics.BitmapWrapper;
import com.stencyl.graphics.ColorMatrixShader;
import com.stencyl.graphics.G;
import com.stencyl.graphics.SheetAnimation;
#if com.stencyl.label
import com.stencyl.label.Label;
#end

import com.stencyl.behavior.Behavior;
import com.stencyl.behavior.BehaviorInstance;
import com.stencyl.behavior.BehaviorManager;
import com.stencyl.behavior.TimedTask;

import com.stencyl.event.Event;

import com.stencyl.models.actor.Group;
import com.stencyl.models.actor.Collision;
import com.stencyl.models.actor.CollisionPoint;
import com.stencyl.models.actor.ActorTweenProperties;
import com.stencyl.models.actor.ActorType;
import com.stencyl.models.actor.Animation;
import com.stencyl.models.actor.Sprite as StencylSprite;
import com.stencyl.models.scene.layers.RegularLayer;
import com.stencyl.models.scene.ActorInstance;
import com.stencyl.models.scene.Layer;
import com.stencyl.models.GameModel;

import com.stencyl.utils.motion.*;
import com.stencyl.utils.ColorMatrix;
import com.stencyl.utils.Log;
import com.stencyl.utils.Utils;

import box2D.dynamics.B2Body;
import box2D.dynamics.B2BodyDef;
import box2D.dynamics.B2Fixture;
import box2D.dynamics.B2FixtureDef;
import box2D.dynamics.B2World;
import box2D.collision.shapes.B2Shape;
import box2D.collision.shapes.B2PolygonShape;
import box2D.collision.shapes.B2CircleShape;
import box2D.collision.shapes.B2EdgeShape;
import box2D.collision.shapes.B2MassData;
import box2D.dynamics.contacts.B2Contact;
import box2D.dynamics.contacts.B2ContactEdge;
import box2D.common.math.B2Vec2;
import box2D.common.math.B2Transform;
import box2D.collision.B2WorldManifold;

import com.stencyl.models.collision.CollisionInfo;
import com.stencyl.models.collision.Grid;
import com.stencyl.models.collision.Hitbox;
import com.stencyl.models.collision.Masklist;
import com.stencyl.models.collision.Mask;

import haxe.CallStack;

#if (haxe_ver >= 4.1)
import Std.isOfType as isOfType;
#else
import Std.is as isOfType;
#end

using com.stencyl.event.EventDispatcher;

#if use_actor_tilemap
typedef ActorAnimation = SheetAnimation;
#else
typedef ActorAnimation = BitmapAnimation;
#end

class Actor extends #if use_actor_tilemap TileContainer #else Sprite #end
{	
	//*-----------------------------------------------
	//* Globals
	//*-----------------------------------------------
	
	private var engine:Engine;
	
	public static function resetStatics():Void
	{
		lastCollided = null;
		manifold = new B2WorldManifold();
	}

	//*-----------------------------------------------
	//* Properties
	//*-----------------------------------------------
	
	//Used for recycled actors to tell them apart
	public var createTime:Float;
	
	#if use_actor_tilemap
	public var name:String;
	#end
	
	public var ID:Int;
	public var groupID:Int;
	public var cachedLayer:Layer;
	public var layer:Layer;
	public var typeID:Int;
	public var type:ActorType;
	
	public static inline var GROUP_OFFSET:Int = 1000000; //for collision reporting
	
	
	//*-----------------------------------------------
	//* States
	//*-----------------------------------------------

	public var recycled:Bool;
	public var paused:Bool;
	
	public var isRegion:Bool;
	public var isTerrainRegion:Bool;
	public var isTerrain:Bool;

	public var destroyed:Bool;	
	public var drawActor:Bool;	
	public var isHUD:Bool;
	public var alwaysSimulate:Bool;
	
	public var isCamera:Bool;
	public var killLeaveScreen:Bool;	
	public var physicsMode:PhysicsMode;
	public var autoScale:Bool;
	
	public var dead:Bool; //gone from the game - don't touch
	public var dying:Bool; //in the process of dying but not yet removed
	
	public var fixedRotation:Bool;
	public var ignoreGravity:Bool;
	public var defaultGravity:Bool;
	public var collidable:Bool;
	public var solid:Bool; //for non Box2D collisions
	public var resetOrigin:Bool; //fot HTML5 origin setting

	//*-----------------------------------------------
	//* Position / Motion
	//*-----------------------------------------------
	
	public var realX:Float;
	public var realY:Float;
	public var realAngle:Float;
	public var realScaleX:Float;
	public var realScaleY:Float;
	
	var lastX:Float;
	var lastY:Float;
	var lastAngle:Float;
	var lastScale:Point;
	
	public var colX:Float;
	public var colY:Float;

	public var xSpeed:Float;
	public var ySpeed:Float;
	public var rSpeed:Float;
	
	public var continuousCollision:Bool;
	
	public var tweenProps:ActorTweenProperties;
	
	//Cache values
	public var cacheWidth:Float;
	public var cacheHeight:Float;	
	
	//*-----------------------------------------------
	//* Sprite-Based Animation
	//*-----------------------------------------------
	
	private static var recycledAnimation:Animation;
	
	public var currAnimation:ActorAnimation;
	public var currAnimationName:String;
	public var animationMap:Map<String,ActorAnimation>;
	
	public var bitmapFilters:Array<BitmapFilter>;
	#if !(flash || canvas)
	private var filtersAsShader:Shader;
	private var usingSoftwareFilter:Bool;
	#end

	public var sprite:StencylSprite;
	
	public var shapeMap:Map<String,Dynamic>;
	public var originMap:Map<String,B2Vec2>;
	public var defaultAnim:String;
	
	public var currOrigin:Point; //logical coords
	public var currOffset:Point; //logical coords
	public var cacheAnchor:Point; //scaled coords
	
	public var transformObj:Transform;
	public var transformPoint:Point; //scaled coords
	public var transformMatrix:Matrix; //scaled coords
	public var updateMatrix:Bool;
	public var drawMatrix:Matrix; //For use when drawing actor image
	
	#if com.stencyl.label
	public var label:Label;
	#end

	public var attachedImages:Array<BitmapWrapper> = null;
	
	// These are for the smooth movement option.
	public var smoothMove:Bool = false;
	public var firstMove:Bool = false;
	public var snapOnSet:Bool = false;
	public var drawX:Float = 0;
	public var drawY:Float = 0;
	public var moveMultiplier:Float = 0.33;
	public var moveXDistance:Float = 0;
	public var moveYDistance:Float = 0;
	public var minMove:Float = 3;
	public var maxMove:Float = 99999;

	//*-----------------------------------------------
	//* Behaviors
	//*-----------------------------------------------
	
	public var behaviors:BehaviorManager;
	public var customizedBehaviors:Bool = false;
	
	
	//*-----------------------------------------------
	//* Actor Values
	//*-----------------------------------------------
	
	public var registry:Map<String,Dynamic>;

	
	//*-----------------------------------------------
	//* Events
	//*-----------------------------------------------	
	
	public var allListeners:Map<Int,Array<Dynamic>>;
	public var allEventReferences:Array<Dynamic>;
	
	public var whenCreated:Event<Void->Void>;
	public var whenUpdated:Event<Float->Void>;
	public var whenDrawing:Event<G->Float->Float->Void>;
	public var whenKilled:Event<Void->Void>;
	public var whenMousedOver:Event<Int->Void>;
	public var whenPositionStateChanged:Event<Bool->Bool->Bool->Bool->Void>;
	public var whenCollided:Event<Collision->Void>;
	
	public var mouseState:Int;
	public var lastScreenState:Bool;
	public var lastSceneState:Bool;
	
	//Purely used by Engine.hx for caching. Don't rely on or use internally!
	public var isOnScreenCache:Bool;
	
	
	//*-----------------------------------------------
	//* Physics (Box2D)
	//*-----------------------------------------------
	
	public var body:B2Body;
	public var bodyDef:B2BodyDef;
	public var md:B2MassData;
	public var bodyScale:Point;
	
	public var handlesCollisions:Bool;
	public var contacts:IntHashTable<B2Contact>;
	public var regionContacts:IntHashTable<B2Contact>;
	public var collisions:IntHashTable<Collision>;
	
	public var dummy:B2Vec2;
	public var zero:B2Vec2;
	
	//*-----------------------------------------------
	//* Collisions
	//*-----------------------------------------------

	public static var lastCollided:Actor;
	
	//*-----------------------------------------------
	//* Init
	//*-----------------------------------------------

	public function new
	(
		engine:Engine, 
		ID:Int,
		groupID:Int,
		x:Float=0, 
		y:Float=0, 
		layerID:Int=-1, 
		width:Float=32, 
		height:Float=32,
		sprite:StencylSprite=null,
		behaviorValues:Map<String,BehaviorInstance>=null,
		actorType:ActorType=null,
		bodyDef:B2BodyDef=null,
		isSensor:Bool=false,
		isStationary:Bool=false,
		isKinematic:Bool=false,
		canRotate:Bool=false,
		shape:Dynamic=null, //B2Shape or Mask - Used only for terrain.
		autoScale:Bool = true,
		ignoreGravity:Bool = false,
		physicsMode:PhysicsMode = NORMAL_PHYSICS
	)
	{
		super();
		
		if(Engine.NO_PHYSICS && physicsMode == NORMAL_PHYSICS)
		{
			physicsMode = SIMPLE_PHYSICS;
			this.physicsMode = SIMPLE_PHYSICS;
		}
		
		//---
		
		dummy = new B2Vec2();
		zero = new B2Vec2(0, 0);
		
		_point = Utils.point;
		_moveX = _moveY = 0;
		
		HITBOX = new Mask();		
		set_shape(HITBOX);
		
		if(isOfType(this, Region) && Engine.NO_PHYSICS)
		{
			shape = HITBOX = new Hitbox(Std.int(width), Std.int(height), 0, 0, false, -2);
			set_shape(shape);
		}
		
		//---
		this.x = 0;
		this.y = 0;
		this.rotation = 0;		
		
		realX = 0;
		realY = 0;
		realAngle = 0;
		realScaleX = 1;
		realScaleY = 1;
		
		collidable = true;
		solid = !isSensor;
		updateMatrix = true;
		
		colX = 0;
		colY = 0;
		
		//---
		
		lastScale = new openfl.geom.Point(1, 1);
		lastX = -1000;
		lastY = -1000;
		lastAngle = 0;		
		
		tweenProps = new ActorTweenProperties();
		tweenProps.xy.doOnUpdate(updateTweenXY);
		tweenProps.angle.doOnUpdate(updateTweenAngle);
		tweenProps.alpha.doOnUpdate(updateTweenAlpha);
		tweenProps.realScaleXY.doOnUpdate(updateTweenScaleXY);
		
		transformPoint = new Point(0, 0);
		transformMatrix = new Matrix();
		drawMatrix = new Matrix();
		
		currOrigin = new Point(0, 0);
		currOffset = new Point(0, 0);			
		registry = new Map<String,Dynamic>();
		
		attachedImages = new Array<BitmapWrapper>();
		
		this.physicsMode = physicsMode;
		this.autoScale = autoScale;
		xSpeed = 0;
		ySpeed = 0;
		rSpeed = 0;
		
		mouseState = 0;
		
		lastScreenState = false;
		lastSceneState = false;	
		isOnScreenCache = false;		
		
		isCamera = false;
		isRegion = false;
		isTerrainRegion = false;
		drawActor = true;
		
		killLeaveScreen = false;
		alwaysSimulate = false;
		isHUD = false;
		continuousCollision = false;

		fixedRotation = false;
		this.ignoreGravity = ignoreGravity;
		defaultGravity = ignoreGravity;
		resetOrigin = true;
		
		//---
		
		allListeners = new Map<Int,Array<Dynamic>>();
		allEventReferences = new Array<Dynamic>();
		
		whenCreated = new Event<Void->Void>();
		whenUpdated = new Event<Float->Void>();
		whenDrawing = new Event<G->Float->Float->Void>();
		whenKilled = new Event<Void->Void>();
		whenMousedOver = new Event<Int->Void>();
		whenPositionStateChanged = new Event<Bool->Bool->Bool->Bool->Void>();
		whenCollided = new Event<Collision->Void>();
		
		//---
		
		this.recycled = false;
		this.paused = false;
		this.destroyed = false;
		
		this.name = "Unknown";
		this.ID = ID;
		this.groupID = groupID;
		this.typeID = actorType != null ? actorType.ID : -1;
		this.engine = engine;
		
		collidedList = new Array<Actor>();
		
		collisions = new IntHashTable<Collision>(16);
		simpleCollisions = new IntHashTable<Collision>(16);
		contacts = new IntHashTable<B2Contact>(16);
		regionContacts = new IntHashTable<B2Contact>(16);
		
		collisions.reuseIterator = true;
		simpleCollisions.reuseIterator = true;
		contacts.reuseIterator = true;
		regionContacts.reuseIterator = true;
		
		contactCount = 0;
		collisionsCount = 0;
		
		handlesCollisions = true;
		
		//---
		
		behaviors = new BehaviorManager();
		
		//---
		
		currAnimationName = "";
		animationMap = new Map<String,ActorAnimation>();
		shapeMap = new Map<String,Dynamic>();
		originMap = new Map<String,B2Vec2>();
		
		this.sprite = sprite;
		this.type = actorType;
		
		//---
		
		if(sprite != null)
		{
			for(a in sprite.animations)
			{
				addAnim(a);
				
				if(a.animID == sprite.defaultAnimation)
				{
					defaultAnim = a.animName;
				}
			}
		}
		
		//--
		
		if(recycledAnimation == null)
			recycledAnimation = new Animation(-1, "recyclingDefault", null, null, null, false, false, 1, 1, 0, 0, [10], 1, 1, 1);
		addAnim(recycledAnimation);

		if(bodyDef != null && physicsMode == NORMAL_PHYSICS)
		{
			if(bodyDef.bullet)
			{
				B2World.m_continuousPhysics = true;
			}
			
			bodyDef.groupID = groupID;

			initFromBody(bodyDef);	
			
			//XXX: Box2D seems to require this to be done, otherwise it will refuse to create any shapes in the future!
			var box = new B2PolygonShape();
			box.setAsBox(1, 1);
			body.createFixture2(box, 0.1);
			
			md = new B2MassData();
			md.mass = bodyDef.mass;
			md.I = bodyDef.aMass;
			md.center.x = 0;
			md.center.y = 0;
			
			body.setMassData(md);
			bodyScale = new Point(1, 1);
		}
		
		else
		{
			if(shape == null || Type.typeof(shape) == TFloat)
			{				
				shape = createBox(width, height);
			}
			
			if(bodyDef != null)
			{
				continuousCollision = bodyDef.bullet;
			}
			
			if(isOfType(this, Region))
			{
				isSensor = true;
				canRotate = false;
			}
			
			if(isOfType(this, Terrain))
			{
				canRotate = false;
			}
			
			if(shape != null && isOfType(shape, com.stencyl.models.collision.Mask))
			{
				set_shape(shape);
				isTerrain = true;
			}
			
			else if(physicsMode == NORMAL_PHYSICS)
			{
				initBody(groupID, isSensor, isStationary, isKinematic, canRotate, shape);
			}
		}

		cacheAnchor = new Point(0, 0);

		switchToDefaultAnimation();
		
		//Use set location to align actors
		if(sprite != null)
		{ 
			setLocation(x, y);
		}
		
		else
		{
			if(shape != null && isOfType(shape, com.stencyl.models.collision.Mask))
			{
				cacheWidth = width;
				cacheHeight = height;
			}
			
			else if(physicsMode == NORMAL_PHYSICS)
			{
				body.setPosition(new B2Vec2(Engine.toPhysicalUnits(x), Engine.toPhysicalUnits(y)));
			}
		}
		
		if(behaviorValues != null)
		{
			customizedBehaviors = true;
		}
		else if(actorType != null) //No IC - Default to what the ActorType uses
		{
			behaviorValues = actorType.behaviorValues;
		}
		
		if(layerID != -1)
		{
			engine.moveActorToLayer(this, cast engine.getLayerById(layerID));
		}
		
		Engine.initBehaviors(behaviors, behaviorValues, this, engine, false);
	}	
	
	public function destroy()
	{
		if(destroyed)
		{
			return;
		}
		
		destroyed = true;
		
		for(anim in animationMap)
		{
			anim.visible = false;
		}
		
		#if !use_actor_tilemap
		Utils.removeAllChildren(this);
		#else
		Utils.removeAllTiles(this);
		#end

		if(body != null && physicsMode == NORMAL_PHYSICS)
		{
			var contact:B2ContactEdge = body.getContactList();
			
			while(contact != null)
			{	
				Engine.engine.world.m_contactManager.m_contactListener.endContact(contact.contact);
				contact = contact.next;
			}
			
			Engine.engine.world.destroyBody(body);
		}
		
		cancelTweens();
		
		lastCollided = null;
		
		shapeMap = null;
		originMap = null;
		defaultAnim = null;
		animationMap = null;
		currAnimation = null;
		currOffset = null;
		currOrigin = null;
		body = null;
		sprite = null;
		contacts = null;
		regionContacts = null;
		contactCount = 0;
		collisionsCount = 0;
		
		transformPoint = null;
		transformMatrix = null;
		
		whenCreated = null;
		whenUpdated = null;
		whenDrawing = null;
		whenKilled = null;
		whenMousedOver = null;
		whenPositionStateChanged = null;
		whenCollided = null;
		allListeners = null;
		allEventReferences = null;
		
		registry = null;
		
		for(k in collisions.keys()) 
		{
			var d = collisions.get(k);
			while(d.points.length > 0)
				CollisionPoint.free(d.points.pop());
		}
		
		collisions = null;
		simpleCollisions = null;		
		
		if(bodyDef != null)
		{
			bodyDef.userData = null;
			bodyDef = null;
		}
		
		behaviors.destroy();
	}
	
	public function resetListeners()
	{
		for (key in allListeners.keys())
		{
			allListeners.remove(key);
		}
		
		while (allEventReferences.length > 0)
		{
			allEventReferences.pop();
		}
		
		if (whenUpdated.length > 0)
		{
			whenUpdated.removeAll();
		}
		
		if (whenDrawing.length > 0)
		{
			whenDrawing.removeAll();
		}
		
		if (whenKilled.length > 0)
		{
			whenKilled.removeAll();
		}
		
		if (whenMousedOver.length > 0)
		{
			whenMousedOver.removeAll();
		}
		
		if (whenPositionStateChanged.length > 0)
		{
			whenPositionStateChanged.removeAll();
		}
		
		if (whenCollided.length > 0)
		{
			whenCollided.removeAll();
		}
	}
	
	private var defaultHitbox:Hitbox;
	private var defaultMasklist:Masklist;
	
	public function addAnim(anim:Animation)
	{
		var shapes = (physicsMode == NORMAL_PHYSICS) ? anim.physicsShapes : anim.simpleShapes;
		
		if(shapes != null)
		{
			var arr = new Array<Dynamic>();
			
			if(physicsMode == SIMPLE_PHYSICS)
			{
				for(s in shapes)
				{				
					if(isOfType(s, Hitbox) && physicsMode != NORMAL_PHYSICS)
					{		
						s = cast(s, Hitbox).clone();
						s.assignTo(this);
					}
				
					arr.push(s);
				}
			}
			
			else if(physicsMode == MINIMAL_PHYSICS)
			{
				//no shapes at all
			}
			
			else
			{
				for(s in shapes)
				{				
					arr.push(s);
				}
			}
			
			if(physicsMode != NORMAL_PHYSICS)
			{
				shapeMap.set(anim.animName, new Masklist(arr, this));
			}
			
			else
			{
				shapeMap.set(anim.animName, arr);
			}
		}
		
		animationMap.set(anim.animName, new ActorAnimation(anim));
		originMap.set(anim.animName, new B2Vec2(anim.originX, anim.originY));
	}

	public function reloadAnimationGraphics(animID:Int):Void
	{
		if(animID == -1)
		{
			for(a in sprite.animations)
			{
				var actorAnim = animationMap.get(a.animName);
				actorAnim.framesUpdated();
			}
			updateChildrenPositions();
		}
		else
		{
			var a = sprite.animations.get(animID);
			var actorAnim = animationMap.get(a.animName);
			actorAnim.framesUpdated();
			if(actorAnim == currAnimation)
			{
				updateChildrenPositions();
			}
		}
	}

	public function initScripts()
	{		
		if(physicsMode == MINIMAL_PHYSICS)
		{
			handlesCollisions = false;
			return;
		}
	
		handlesCollisions = true;
		behaviors.initScripts();
		
		whenCreated.dispatch();
	}
	
	static public function createBox(width:Float, height:Float):B2PolygonShape
	{
		var boxShape:B2PolygonShape = new B2PolygonShape();
		boxShape.setAsBox(Engine.toPhysicalUnits(width/2), Engine.toPhysicalUnits(height/2));
		return boxShape;
	}
	
	private function initFromBody(bodyDef:B2BodyDef)
	{	
		bodyDef.allowSleep = false;
		bodyDef.userData = this;
		this.bodyDef = bodyDef;
		body = Engine.engine.world.createBody(bodyDef);
	}

	private function initBody(groupID:Int, isSensor:Bool, isStationary:Bool, isKinematic:Bool, canRotate:Bool, shape:Dynamic)
	{			
		var bodyDef:B2BodyDef = new B2BodyDef();
		
		bodyDef.groupID = groupID;
		bodyDef.position.x = Engine.toPhysicalUnits(x);
		bodyDef.position.y = Engine.toPhysicalUnits(y);
			
		bodyDef.angle = 0;
		bodyDef.fixedRotation = !canRotate;
		bodyDef.allowSleep = false;

		if(isStationary)
		{
			bodyDef.type = B2Body.b2_staticBody;
		}
		
		else if(isKinematic)
		{
			bodyDef.type = B2Body.b2_kinematicBody;
		}
		
		else
		{
			bodyDef.type = B2Body.b2_dynamicBody;
		}
		
		if(isOfType(shape, Array))
		{
			bodyDef.userData = this;
			body = Engine.engine.world.createBody(bodyDef);			
				
			var arr:Array<Dynamic> = cast(shape, Array<Dynamic>);
		
			for(item in arr)
			{
				var fixtureDef:B2FixtureDef = new B2FixtureDef();
				fixtureDef.shape = item;
				fixtureDef.friction = 1.0;
				fixtureDef.density = 0.1;
				fixtureDef.restitution = 0;
				fixtureDef.isSensor = false;
				fixtureDef.groupID = GameModel.TERRAIN_ID;
				fixtureDef.userData = this;
							
				body.createFixture(fixtureDef);
			}
		}

		else
		{
			var fixtureDef:B2FixtureDef = new B2FixtureDef();
			fixtureDef.shape = shape;
			fixtureDef.friction = 1.0;
			fixtureDef.density = 0.1;
			fixtureDef.restitution = 0;
			fixtureDef.isSensor = isSensor;
			fixtureDef.groupID = GameModel.INHERIT_ID;
			fixtureDef.userData = this;
						
			bodyDef.userData = this;
			body = Engine.engine.world.createBody(bodyDef);			
			body.createFixture(fixtureDef);
		}

		this.bodyDef = bodyDef;
	}   	
   	
   	//*-----------------------------------------------
	//* Animation
	//*-----------------------------------------------
   	
	public function addAnimation(name:String, sprite:ActorAnimation)
	{
		animationMap.set(name, sprite);
	}
	
	public function getAnimation():String
	{
		return currAnimationName;
	}
	
	public function setAnimation(name:String)
	{
		switchAnimation(name);
	}
	
	public function switchToDefaultAnimation()
	{
		if(defaultAnim != null)
		{
			switchAnimation(defaultAnim, defaultShapeChanged());
			setCurrentFrame(0);
		}
	}
	
	public function isAnimationPlaying():Bool
	{
		return !currAnimation.isFinished();
	}
	
	public function getCurrentFrame():Int
	{
		return currAnimation.getCurrentFrame();
	}
	
	public function setCurrentFrame(frame:Int)
	{
		currAnimation.setFrame(frame);
	}
	
	public function getNumFrames():Int
	{
		return currAnimation.getNumFrames();
	}
	
	public function defaultShapeChanged() // added to fix http://community.stencyl.com/index.php?issue=390.0
	{
		if (physicsMode != NORMAL_PHYSICS)
		{
			return true;
		}
	
		var arrDefault = shapeMap.get(defaultAnim);
		
		if (getBody() == null || getBody().getFixtureList() == null || getBody().getFixtureList().getShape() == null)
		{
			if (arrDefault != null && arrDefault.length > 0)
			{
				return true;
			}
		}
		else
		{
			if (arrDefault == null || arrDefault.length == 0)
			{
				return true;
			}
			else
			{
				if (arrDefault.length > 1)
				{
					return true;
				}
				else
				{
					var defaultDef:B2FixtureDef = arrDefault[0];
					
					if (defaultDef == null)
					{
						return true;
					}
					else
					{
						var currFixture = getBody().getFixtureList();
						var currShape:B2Shape = getBody().getFixtureList().getShape();
						var defaultShape:B2Shape = defaultDef.shape;
						
						if (currFixture.groupID != defaultDef.groupID)
						{
							return true;
						}

						if (getBody().getFixtureList().isSensor() != defaultDef.isSensor)
						{
							return true;
						}
						else if(Type.getClass(currShape) == Type.getClass(defaultShape))
						{
							if(Type.getClass(currShape) == B2PolygonShape)
							{
								var polyOld:B2PolygonShape = cast currShape;
								var polyNew:B2PolygonShape = cast defaultShape;
								
								if(polyOld.m_vertexCount != polyNew.m_vertexCount)
								{
									return true;
								}
								
								else
								{
									for(i in 0...polyOld.m_vertexCount)
									{
										if(polyOld.m_vertices[i].x != polyNew.m_vertices[i].x)
										{
											return true;
											break;
										}
										
										else if(polyOld.m_vertices[i].y != polyNew.m_vertices[i].y)
										{
											return true;
											break;
										}
									}
								}
							}
							
							else if(Type.getClass(currShape) == B2CircleShape)
							{
								var circleOld:B2CircleShape = cast currShape;
								var circleNew:B2CircleShape = cast defaultShape;
								
								if(circleOld.m_radius != circleNew.m_radius || 
								   circleOld.m_p.x != circleNew.m_p.x || 
								   circleOld.m_p.y != circleNew.m_p.y)
								{
									return true;
								}
							}
						}
						
						else
						{
							return true;
						}
					}
				}
			}
		}
		
		return false;
	}
	
	public function switchAnimation(name:String, defaultShapeChanged:Bool = false)
	{
		if(name != currAnimationName || defaultShapeChanged)
		{
			var newAnimation = animationMap.get(name);
			
			if(newAnimation == null)
			{
				return;
			}
			
			if(currAnimation != null)
			{
				#if !use_actor_tilemap
				removeChild(currAnimation);
				#else
				removeTile(currAnimation);
				#end
			}
			
			//---
			
			var isDifferentShape = defaultShapeChanged;
			
			//XXX: Only switch the animation shape if it's different from before.
			//http://community.stencyl.com/index.php/topic,16464.0.html
			//TODO: This is similar to defaultShapeChanged(). See if they can be combined.
			if(body != null && physicsMode == NORMAL_PHYSICS && !isDifferentShape)
			{
				var arrOld = shapeMap.get(currAnimationName);
				var arrNew = shapeMap.get(name);
				
				if(arrOld == null || arrNew == null)
				{
					isDifferentShape = true;
				}
			
				else
				{
					if(arrOld.length != arrNew.length || arrOld.length > 1)
					{
						isDifferentShape = true;
					}
					
					else
					{
						var oldDef:B2FixtureDef = arrOld[0];
						var newDef:B2FixtureDef = arrNew[0];
						
						if(oldDef == null || newDef == null)
						{
							isDifferentShape = true;
						}
					
						else
						{
							var oldShape = oldDef.shape;
							var newShape = newDef.shape;
							
							if(oldDef.isSensor != newDef.isSensor)
							{
								isDifferentShape = true;
							}
							
							else if(oldDef.groupID != newDef.groupID)
							{
								isDifferentShape = true;
							}
							
							else if(Type.getClass(oldShape) == Type.getClass(newShape))
							{
								if(Type.getClass(oldShape) == B2PolygonShape)
								{
									var polyOld:B2PolygonShape = cast oldShape;
									var polyNew:B2PolygonShape = cast newShape;
									
									if(polyOld.m_vertexCount != polyNew.m_vertexCount)
									{
										isDifferentShape = true;
									}
									
									else
									{
										for(i in 0...polyOld.m_vertexCount)
										{
											if(polyOld.m_vertices[i].x != polyNew.m_vertices[i].x)
											{
												isDifferentShape = true;
												break;
											}
											
											else if(polyOld.m_vertices[i].y != polyNew.m_vertices[i].y)
											{
												isDifferentShape = true;
												break;
											}
										}
									}
								}
								
								else if(Type.getClass(oldShape) == B2CircleShape)
								{
									var circleOld:B2CircleShape = cast oldShape;
									var circleNew:B2CircleShape = cast newShape;
									
									if(circleOld.m_radius != circleNew.m_radius || 
									   circleOld.m_p.x != circleNew.m_p.x || 
									   circleOld.m_p.y != circleNew.m_p.y)
									{
										isDifferentShape = true;
									}
								}
							}
							
							else
							{
								isDifferentShape = true;
							}
						}
					}
				}
			}
			
			//---
			
			currAnimationName = name;
			currAnimation = newAnimation;
			#if !(flash || canvas)
			{
				#if !use_actor_tilemap
				if(bitmapFilters != null && usingSoftwareFilter)
				{
					currAnimation.filter = bitmapFilters;
				}
				else
				{
					currAnimation.filter = null;
				}
				#end
			}
			currAnimation.shader = filtersAsShader;
			#else
			currAnimation.filter = bitmapFilters;
			#end
			currAnimation.visible = drawActor;

			#if !use_actor_tilemap
			addChild(newAnimation);
			#else
			addTile(newAnimation);
			#end
			
			//----------------
			
			var animOrigin:B2Vec2 = originMap.get(name);		
			
			var centerx = (currAnimation.width / Engine.SCALE / 2) - animOrigin.x;
			var centery = (currAnimation.height / Engine.SCALE / 2) - animOrigin.y;
			
			if(body != null && isDifferentShape && physicsMode == NORMAL_PHYSICS)
			{
				//Remember regions
				var regions = new Array<Region>();
			
				//BEGIN EXPLICIT ENDCONTACT HACK
				//SECRET/showthread.php?tid=9564
				var contact = body.getContactList();
				
				while(contact != null)
				{
					if(isOfType(contact.other.getUserData(), Region) && contact.contact.isTouching())
					{
						regions.push(cast contact.other.getUserData());
					}
					
					Engine.engine.world.m_contactManager.m_contactListener.endContact(contact.contact);
					contact = contact.next;
				}
				
				//Catch any residual contacts.
				//SECRET/showthread.php?tid=9773&page=3
				for(k in collisions.keys()) 
				{
					var d = collisions.get(k);
					while(d.points.length > 0)
						CollisionPoint.free(d.points.pop());
					collisions.unset(k);
				}
				
				collisions = new IntHashTable<Collision>(16);
				simpleCollisions = new IntHashTable<Collision>(16);
				contacts = new IntHashTable<B2Contact>(16);
				regionContacts = new IntHashTable<B2Contact>(16);
				
				collisions.reuseIterator = true;
				simpleCollisions.reuseIterator = true;
				contacts.reuseIterator = true;
				regionContacts.reuseIterator = true;
				
				contactCount = 0;
				collisionsCount = 0;
				
				//END HACK

				while(body.m_fixtureCount > 0)
				{			
					body.DestroyFixture(body.getFixtureList());
				}
				
				for(f in cast(shapeMap.get(name), Array<Dynamic>))
				{
					var originFixDef = new B2FixtureDef();
					
					if(bodyDef.friction < Utils.NUMBER_MAX_VALUE)
					{
						originFixDef.friction = bodyDef.friction;
						originFixDef.restitution = bodyDef.bounciness;							
						
						if(bodyDef.mass > 0)
						{
							originFixDef.density = 0.1;//bodyDef.mass;
						}
					}
					
					originFixDef.density = f.density;						
					originFixDef.isSensor = f.isSensor;
					originFixDef.groupID = f.groupID;
					originFixDef.shape = f.shape;

					//TODO: Origin point junk goes here
					if (animOrigin != null)
					{
						body.origin.x = Engine.toPhysicalUnits(-animOrigin.x);
						body.origin.y = Engine.toPhysicalUnits(-animOrigin.y);
						
						if (isOfType(f.shape, B2PolygonShape))
						{
							var xf:B2Transform = new B2Transform();
							var oldBox:B2PolygonShape = cast f.shape;
							var newBox:B2PolygonShape = new B2PolygonShape();
								
							newBox.setAsArray(oldBox.m_vertices, oldBox.m_vertices.length);
								
							var vertices:Array<B2Vec2> = newBox.m_vertices;
							var normals:Array<B2Vec2> = newBox.m_normals;										
												
							xf.position.set(Engine.toPhysicalUnits(centerx), Engine.toPhysicalUnits(centery));
							xf.R.setAngle(0);
							
							for (i in 0...newBox.m_vertexCount) 
							{								
								vertices[i] = xf.multiply(vertices[i]);
								normals[i] = xf.R.multiplyV(normals[i]);															
							}
							
							newBox.setAsArray(vertices, vertices.length);							
							newBox.m_normals = normals;
							
							originFixDef.shape = newBox;
						}
						
						else if (isOfType(f.shape, B2CircleShape))
						{
							var oldCircle:B2CircleShape = cast f.shape;
							var newCircle:B2CircleShape = new B2CircleShape();
								
							newCircle.setRadius(oldCircle.getRadius());
							newCircle.m_p.x = oldCircle.m_p.x + Engine.toPhysicalUnits(centerx);
							newCircle.m_p.y = oldCircle.m_p.y + Engine.toPhysicalUnits(centery);
							
							originFixDef.shape = newCircle;
						}
					}
					
					var fix = body.createFixture(originFixDef);
					fix.SetUserData(this);	
				}
				
				if(body.getFixtureList() != null)
				{
					bodyScale.x = 1;
					bodyScale.y = 1;
			
					for(r in regions)
					{
						var mine = body.getFixtureList().m_aabb;
						var other = r.getBody().getFixtureList().m_aabb;
						
						if(other.testOverlap(mine))
						{
							r.addActor(this);
						}
					}
				}
				
				if(md != null)
				{
					body.setMassData(md);
				}
			}	
						
			else if(shapeMap.get(name) != null && physicsMode == SIMPLE_PHYSICS)
			{				
				//Get hitbox list for Simple Physics
				set_shape(shapeMap.get(name));
				HITBOX = _mask;
				
				//TODO: Compare hitboxes
				isDifferentShape = true;
			}
			
			cacheWidth = currAnimation.width / Engine.SCALE;
			cacheHeight = currAnimation.height / Engine.SCALE;			
			
			if(body != null)
			{
				body.size.x = Engine.toPhysicalUnits(cacheWidth);
				body.size.y = Engine.toPhysicalUnits(cacheHeight);
			}
			
			if(physicsMode == NORMAL_PHYSICS)
			{
				realX = getX(false);
				realY = getY(false);
				
				updateBodyScale();
			}
			
			if(animOrigin != null)
			{					
				setOriginPoint(Std.int(animOrigin.x), Std.int(animOrigin.y));				
			}
			
			updateChildrenPositions();
			
			updateMatrix = true;
			
			//----------------
			
			currAnimation.reset();
			currAnimation.activate();
		}
	}
	
	public function updateChildrenPositions()
	{
		var newAnchor = (currAnimation != null) ?
			new Point(-currAnimation.x, -currAnimation.y) :
			new Point(0, 0);
		
		if(!newAnchor.equals(cacheAnchor))
		{
			cacheAnchor.copyFrom(newAnchor);
			for(img in attachedImages)
			{
				img.updatePosition();
			}
			#if com.stencyl.label
			if(label != null)
			{
				label.updatePosition();
			}
			#end
		}
	}

	public function removeAttachedImages()
	{
		for(b in attachedImages)
		{
			b.cacheParentAnchor = Utils.zero;
			#if !use_actor_tilemap
			removeChild(b);
			#else
			removeTile(b);
			#end
		}
		attachedImages = new Array<BitmapWrapper>();
	}
	
	//*-----------------------------------------------
	//* Events - Update
	//*-----------------------------------------------
	
	public function update(elapsedTime:Float)
	{
		innerUpdate(elapsedTime, true);
	}
	
	public function innerUpdate(elapsedTime:Float, hudCheck:Bool)
	{
		//HUD / always simulate actors are updated separately to prevent double updates.
		if(paused || isCamera || dying || dead || destroyed || hudCheck && (isHUD || alwaysSimulate))
		{
			return;
		}
		
		if(whenMousedOver.length > 0)
		{
			//Previously was checkMouseState() - inlined for performance. See Region:innerUpdate for other instance
			var mouseOver:Bool = isMouseOver();
			
			if(mouseOver)
			{
				if(mouseState <= 0)
				{
					//Just Entered
					mouseState = 1;
					whenMousedOver.dispatch(mouseState);
				}
				else
				{
					//Over
					mouseState = 2;
				}
				
				if(Input.mousePressed)
				{
					//Clicked On
					mouseState = 3;
					whenMousedOver.dispatch(mouseState);
				}
				
				else if(Input.mouseDown)
				{
					//Dragged
					mouseState = 4;
					whenMousedOver.dispatch(mouseState);
				}
				
				if(Input.mouseReleased)
				{
					//Released
					mouseState = 5;
					whenMousedOver.dispatch(mouseState);
				}
			}
			
			else
			{
				if(mouseState > 0)
				{
					//Just Exited
					mouseState = -1;
					whenMousedOver.dispatch(mouseState);
				}
				
				else if(mouseState == -1)
				{
					mouseState = 0;
				}
			}
		}
		
		var checkType = type.ID;
		var groupType = GROUP_OFFSET + groupID;
		
		var ec = engine.whenCollidedEvents;
		var ep = engine.whenTypeGroupPositionStateChangedEvents;
				
		if(physicsMode == NORMAL_PHYSICS)
		{
			if(whenCollided.length > 0 || 
			   ec.get(checkType) != null || 
			   ec.get(groupType) != null) 
			{
				//TODO: This needs to be optimized a lot.
				handleCollisions();		
			}
		}
		
		internalUpdate(elapsedTime, true);		
		
		if (physicsMode == SIMPLE_PHYSICS)
		{
			if(whenCollided.length > 0 || 
			   ec.get(checkType) != null || 
			   ec.get(groupType) != null) 
			{
				handleCollisionsSimple();
			}
			disposeRemovedCollisionInfo();
		}
		
		if(physicsMode != MINIMAL_PHYSICS)
		{
			whenUpdated.dispatch(elapsedTime);		
		}
		
		if(whenPositionStateChanged.length > 0 || 
		   ep.get(checkType) != null || 
		   ep.get(groupType) != null)
		{
			checkScreenState();
		}
		
		#if com.stencyl.label
		//If this actor has a label, set the label's alpha to match the actor's alpha.
		if(label != null)
		{
			label.setAlpha(alpha);
		}
		#end
	}
	
	//doAll prevents super.update from being called, which can often muck with
	//animations happening if they are updated before play() is called.
	public function internalUpdate(elapsedTime:Float, doAll:Bool)
	{
		if(paused)
		{
			return;
		}
					
		if(physicsMode != NORMAL_PHYSICS)
		{		
			if(physicsMode == SIMPLE_PHYSICS && !ignoreGravity && !isHUD)
			{
				//TODO: Adjust?
				xSpeed += elapsedTime * engine.gravityX * 0.001;
				ySpeed += elapsedTime * engine.gravityY * 0.001;
			}
			
			if(xSpeed != 0 || ySpeed != 0)
			{
				resetReal(realX, realY);			
				
				moveActorBy(elapsedTime * xSpeed * (10 / Engine.STEP_SIZE) * 0.01, elapsedTime * ySpeed * (10 / Engine.STEP_SIZE) * 0.01, false);
			}			
						
			if(rSpeed != 0)
			{
				realAngle += elapsedTime * rSpeed * 0.001;				
			}
			
			if(fixedRotation)
			{
				realAngle = 0;
				this.rSpeed = 0;
			}			
		}
		
		else
		{			
			var p = body.getPosition();		
						
			realX = p.x * Engine.physicsScale;
			realY = p.y * Engine.physicsScale;				
			
			resetReal(realX, realY);
			
			realAngle = body.getAngle() * Utils.DEG;				
		}
		
		if (lastX != realX || lastY != realY || lastAngle != realAngle || lastScale.x != realScaleX || lastScale.y != realScaleY)
		{
			updateMatrix = true;
		}
		
		lastX = realX;
		lastY = realY;
		lastAngle = realAngle;
		lastScale.x = realScaleX;
		lastScale.y = realScaleY;
		
		if(doAll && currAnimation != null)
		{
   			currAnimation.update(elapsedTime);
		}
	}	
	
	public function updateDrawingMatrix(force:Bool = false)
	{
		if(paused && !force)
		{
			return;
		}

		if(smoothMove)
		{
			if(!firstMove)
			{
				drawX = realX;
				drawY = realY;
				firstMove = true;
			}
			
			moveXDistance = realX - drawX;
			moveYDistance = realY - drawY;
			
			//Check x distance
			if(moveXDistance > minMove)
			{
				if(moveXDistance * moveMultiplier > minMove)
				{
					if(moveXDistance > maxMove)
					{
						drawX = realX;
					}
					
					else
					{
						drawX += moveXDistance * moveMultiplier;
					}
				}
				
				else
				{
					drawX += minMove;
				}
			}
			
			else if(moveXDistance < minMove * -1)
			{
				if(moveXDistance * moveMultiplier < minMove * -1)
				{
					if(moveXDistance < maxMove * -1)
					{
						drawX = realX;
					}
					
					else
					{
						drawX += moveXDistance * moveMultiplier;
					}
				}
				
				else
				{
					drawX -= minMove;
				}
			}
			
			else
			{
				drawX = realX;
			}
				
			//Check y distance
			if(moveYDistance > minMove)
			{
				if(moveYDistance * moveMultiplier > minMove)
				{
					if(moveYDistance > maxMove)
					{
						drawY = realY;
					}
					
					else
					{
						drawY += moveYDistance * moveMultiplier;
					}
				}
				
				else
				{
					drawY += minMove;
				}
			}
			
			else if(moveYDistance < minMove * -1)
			{
				if(moveYDistance * moveMultiplier < minMove * -1)
				{
					if(moveYDistance < maxMove * -1)
					{
						drawY = realY;
					}
					
					else
					{
						drawY += moveYDistance * moveMultiplier;
					}
				}
				
				else
				{
					drawY -= minMove;
				}
			}
			
			else
			{
				drawY = realY;
			}
		}
		
		//Normal Movement
		else
		{
			if(physicsMode != NORMAL_PHYSICS)
			{
				drawX = realX;
				drawY = realY;
			}
			
			else
			{
				var p = body.getPosition();
				
				drawX = p.x * Engine.physicsScale;
				drawY = p.y * Engine.physicsScale;
			}
		}
		
		transformPoint.x = (currOrigin.x - cacheWidth / 2) * Engine.SCALE;
		transformPoint.y = (currOrigin.y - cacheHeight / 2) * Engine.SCALE;

		transformMatrix.identity();
		transformMatrix.translate( -transformPoint.x, -transformPoint.y);
		transformMatrix.scale(realScaleX, realScaleY);
		
		if(realAngle != 0)
		{
			transformMatrix.rotate(realAngle * Utils.RAD);
		}
		
		if (Config.pixelsnap)
		{
			transformMatrix.translate(Math.round(drawX) * Engine.SCALE, Math.round(drawY) * Engine.SCALE);
		}
		
		else
		{
			transformMatrix.translate(drawX * Engine.SCALE, drawY * Engine.SCALE);
		}
		
		#if !use_actor_tilemap
		if(transformObj == null)
		{
			transformObj = transform;
		}
		
		transformObj.matrix = transformMatrix;
		#else
		matrix = transformMatrix;
		#end
	}
	
	public function updateTweenAlpha()
	{
		alpha = tweenProps.alpha.value;
	}
	
	public function updateTweenScaleXY()
	{
		realScaleX = tweenProps.realScaleXY.value1;
		realScaleY = tweenProps.realScaleXY.value2;
		
		updateBodyScale();
	}
	
	public function updateTweenAngle()
	{
		setAngle(tweenProps.angle.value, false);
	}
	
	public function updateTweenXY()
	{
		if(physicsMode == NORMAL_PHYSICS)
		{
			setXY(tweenProps.xy.value1, tweenProps.xy.value2);
		}
		
		else
		{
			moveActorBy(tweenProps.xy.value1 - getX(false), tweenProps.xy.value2 - getY(false), false);
			updateMatrix = true;
		}
		
		if(tweenProps.xy.finished)
		{
			if(currOffset != null)
			{
				resetReal(realX, realY);
			}
		}
	}
	
	public function updateBodyScale()
	{
		if(autoScale && physicsMode == NORMAL_PHYSICS && body != null && bodyDef.type != B2Body.b2_staticBody)
		{
			if(realScaleX != 0 && realScaleY != 0)
			{
				scaleBody(realScaleX, realScaleY);
			}
		}
	}
	
	//*-----------------------------------------------
	//* Events - Other
	//*-----------------------------------------------
	
	//Make more efficient?
	public function scaleBody(width:Float, height:Float)
	{
		var fixtureList:Array<B2Fixture> = new Array<B2Fixture>();
		var fixture:B2Fixture = body.getFixtureList();

		while (fixture != null)
		{
			fixtureList.push(fixture);
			fixture = fixture.getNext();
		}		
			
		for (f in fixtureList)
		{ 
			var poly:B2Shape = f.getShape();
			var center:B2Vec2 = body.getLocalCenter();
			if(isOfType(poly, B2CircleShape))
			{
				var circle:B2CircleShape = cast poly;
				var factorX:Float = (1 / bodyScale.x) * width;					
				var factorY:Float = (1 / bodyScale.y) * height;
				
				var p:B2Vec2 = circle.m_p;
				p.subtract(center);
				p.x = p.x * factorX;
				p.y = p.y * factorY;	
								
				circle.m_p = center.copy();
				circle.m_p.add(p);
				poly.m_radius = poly.m_radius * Math.abs(factorX);								
			}

			else if(isOfType(poly, B2PolygonShape))
			{
				var polygon:B2PolygonShape = cast poly;
  				var verts:Array<B2Vec2> = polygon.m_vertices;
				var newVerts:Array<B2Vec2> = new Array<B2Vec2>();

				var horiChange:Bool = (bodyScale.x > 0 && width < 0) || (bodyScale.x < 0 && width > 0);
				var vertChange:Bool = (bodyScale.y > 0 && height < 0) || (bodyScale.y < 0 && height > 0);
				
				for (v in verts)
				{
					v.subtract(center);
					v.x = v.x * (1 / Math.abs(bodyScale.x)) * Math.abs(width);
					v.y = v.y * (1 / Math.abs(bodyScale.y)) * Math.abs(height);	
					
					if (horiChange)
					{
						v.x = -v.x;
					}
					
					if (vertChange)
					{
						v.y = -v.y;
					}
					
					var newVert:B2Vec2 = center.copy();
					newVert.add(v);

					newVerts.push(newVert);
				}
				
				if (!(horiChange && vertChange) && (horiChange || vertChange))
				{
					newVerts.reverse();
				}

				polygon.setAsArray(newVerts, newVerts.length);   				
			}
		}	
		
		bodyScale.x = width;
		bodyScale.y = height;
		body.size.x = Engine.toPhysicalUnits(cacheWidth * width);
		body.size.y = Engine.toPhysicalUnits(cacheHeight * height);
	}
	
	private function checkScreenState()
	{
		var onScreen:Bool = isOnScreen();
		var inScene:Bool = onScreen || isInScene();
		
		var enteredScreen:Bool = !lastScreenState && onScreen;
		var enteredScene:Bool = !lastSceneState && inScene;
		var exitedScreen:Bool = lastScreenState && !onScreen;
		var exitedScene:Bool = lastSceneState && !inScene;
		
		whenPositionStateChanged.dispatch(enteredScreen, exitedScreen, enteredScene, exitedScene);
			
		var typeEvent = engine.whenTypeGroupPositionStateChangedEvents.get(groupID + Actor.GROUP_OFFSET);
		var groupEvent = engine.whenTypeGroupPositionStateChangedEvents.get(typeID);
		
		if(typeEvent != null)
		{
			typeEvent.dispatch(this, enteredScreen, exitedScreen, enteredScene, exitedScene);
		}
		
		if(groupEvent != null)
		{
			groupEvent.dispatch(this, enteredScreen, exitedScreen, enteredScene, exitedScene);
		}
		
		lastScreenState = onScreen;
		lastSceneState = inScene;
	}
		
	//*-----------------------------------------------
	//* Collision
	//*-----------------------------------------------
	
	private static var manifold = new B2WorldManifold();
	private var contactCount:Int;
	private var collisionsCount:Int;
	
	inline private function handleCollisions()
	{
		var otherActor:Actor;
		var otherShape:B2Fixture;
		var thisShape:B2Fixture;
		
		//Even iteration over blank maps can impact low-end devices. Guard against it.
		if(contactCount > 0)
		{
			var cp_count = 0;
			var cp:CollisionPoint = null;
		
			for(p in contacts)
			{
				var key = p.key;
				
				if(collisions.hasKey(key))
				{
					//need to update points for pre-existing contacts.

					var d:Collision = collisions.get(key);
					//while(d.points.length > 0)
					//d.points.pop();
					
					p.getWorldManifold(manifold);

					for (point in manifold.m_points)
					{
						if (point.x != 0 && point.y != 0)
						{
							cp = d.points[cp_count];
							if(cp == null)
							{
								d.points[cp_count] = CollisionPoint.get
								(
									point.x, 
									point.y, 
									manifold.m_normal.x,
									manifold.m_normal.y
								);
							}
							else
							{
								cp = d.points[cp_count];
								cp.x = point.x;
								cp.y = point.y;
								cp.normalX = manifold.m_normal.x;
								cp.normalY = manifold.m_normal.y;
							}
							++cp_count;
						}
					}
					
					while(d.points.length > cp_count)
						CollisionPoint.free(d.points.pop());
					cp_count = 0;
					
					continue;
				}
				
				var a1:Actor = p.getFixtureA().getUserData();
				var a2:Actor = p.getFixtureB().getUserData();
				
				if(a1 == this)
				{
					otherActor = a2;
					otherShape = p.getFixtureB();
					thisShape = p.getFixtureA();
				}
				
				else
				{
					otherActor = a1;
					otherShape = p.getFixtureA();
					thisShape = p.getFixtureB();
				}
	
				//TODO: We can pool this if it helps.
				var d:Collision = new Collision();
				d.otherActor = otherActor;
				d.otherShape = otherShape;
				d.thisActor = this;
				d.thisShape = thisShape;
				d.actorA = a1;
				d.actorB = a2;

				//TODO: No longer need to remake. Use a shared instance.
				//var manifold = new B2WorldManifold();
				p.getWorldManifold(manifold);
				
				var pt = null;

				collisions.set(key, d);
				collisionsCount++;
				
				var thisActor:Actor = this;
				var body = thisActor.getBody();	
				var otherBody = otherActor.getBody();	
				var body1 = p.getFixtureA().getBody();
				var body2 = p.getFixtureB().getBody();

				//loop over all points in manifold.m_points
				for (point in manifold.m_points)
				{
					//ignore the point if it is (0,0)
					if ((point.x != 0 && point.y != 0) && !(thisShape.isSensor()))
					{
						pt = point;
						
						cp = CollisionPoint.get
						(
							pt.x, 
							pt.y, 
							manifold.m_normal.x,
							manifold.m_normal.y
						);				

						d.points.push(cp);
						
						if(body1 == body)
						{
							d.thisFromBottom = d.thisFromBottom || cp.normalY > 0;
							d.thisFromTop = d.thisFromTop || cp.normalY < 0;
							d.thisFromLeft = d.thisFromLeft || cp.normalX < 0;
							d.thisFromRight = d.thisFromRight || cp.normalX > 0;
						}
						
						else if(body2 == body)
						{
							d.thisFromBottom = d.thisFromBottom || cp.normalY < 0;
							d.thisFromTop = d.thisFromTop || cp.normalY > 0;
							d.thisFromLeft = d.thisFromLeft || cp.normalX > 0;
							d.thisFromRight = d.thisFromRight || cp.normalX < 0;
						}
				
						//---
						
						if(body1 == otherBody)
						{
							d.otherFromBottom = d.otherFromBottom || cp.normalY > 0;
							d.otherFromTop = d.otherFromTop || cp.normalY < 0;
							d.otherFromLeft = d.otherFromLeft || cp.normalX < 0;
							d.otherFromRight = d.otherFromRight || cp.normalX > 0;
						}
						
						else if(body2 == otherBody)
						{
							d.otherFromBottom = d.otherFromBottom || cp.normalY < 0;
							d.otherFromTop = d.otherFromTop || cp.normalY > 0;
							d.otherFromLeft = d.otherFromLeft || cp.normalX > 0;
							d.otherFromRight = d.otherFromRight || cp.normalX < 0;
						}
				
						//---
						
						if(otherActor != null)
						{
							d.thisCollidedWithActor = d.thisCollidedWithActor || (otherActor.groupID != 1 && otherActor.groupID != -2 && !otherActor.isTerrainRegion);					
							d.thisCollidedWithTerrain = d.thisCollidedWithTerrain || otherActor.isTerrainRegion;			
							d.thisCollidedWithTile = d.thisCollidedWithTile || otherActor.groupID == 1;
						}
						
						d.otherCollidedWithActor = d.otherCollidedWithActor || (this.groupID != 1 && this.groupID != -2 && !this.isTerrainRegion);					
						d.otherCollidedWithTerrain = d.otherCollidedWithTerrain || this.isTerrainRegion;			
						d.otherCollidedWithTile = d.otherCollidedWithTile || this.groupID == 1;
						
						d.thisCollidedWithSensor = d.thisCollidedWithSensor || otherShape.isSensor();
						d.otherCollidedWithSensor = d.otherCollidedWithSensor || thisShape.isSensor();		
					}
					else if (thisShape.isSensor())
					{
						if(otherActor != null)
						{
							d.thisCollidedWithActor = d.thisCollidedWithActor || (otherActor.groupID != 1 && otherActor.groupID != -2 && !otherActor.isTerrainRegion);					
							d.thisCollidedWithTerrain = d.thisCollidedWithTerrain || otherActor.isTerrainRegion;			
							d.thisCollidedWithTile = d.thisCollidedWithTile || otherActor.groupID == 1;
						}
						
						d.otherCollidedWithActor = d.otherCollidedWithActor || (this.groupID != 1 && this.groupID != -2 && !this.isTerrainRegion);					
						d.otherCollidedWithTerrain = d.otherCollidedWithTerrain || this.isTerrainRegion;			
						d.otherCollidedWithTile = d.otherCollidedWithTile || this.groupID == 1;
						
						d.thisCollidedWithSensor = d.thisCollidedWithSensor || otherShape.isSensor();
						d.otherCollidedWithSensor = d.otherCollidedWithSensor || thisShape.isSensor();	
					}
				}
			}
		}
		
		//Even iteration over blank maps can impact low-end devices. Guard against it.
		if(collisionsCount > 0)
		{
			for(collision in collisions)
			{
				//Log.verbose(this + " vs " + collision.otherActor);
				
				if
				(
				   collision == null || collision.thisActor == null || collision.otherActor == null ||
				   !collision.thisActor.handlesCollisions || 
				   !collision.otherActor.handlesCollisions)
				{
					continue;
				}
				
				lastCollided = collision.otherActor;
				whenCollided.dispatch(collision);
				
				engine.handleCollision(this, collision);	
			}
		}
	}
	
	public inline function addContact(point:B2Contact)
	{
		if(contacts != null)
		{
			contacts.set(point.key, point);
			contactCount++;
		}
	}
	
	public inline function removeContact(point:B2Contact)
	{
		if(collisions != null)
		{
			var d = collisions.get(point.key);
			if(d != null)
			{
				collisions.unset(point.key);
				collisionsCount--;
				while(d.points.length > 0)
					CollisionPoint.free(d.points.pop());
			}
		}
		
		if(contacts != null)
		{
			if(contacts.unset(point.key))
			{
				contactCount--;
			}
		}
	}
	
	public inline function addRegionContact(point:B2Contact)
	{
		if(regionContacts != null)
		{
			regionContacts.set(point.key, point);
		}			
	}
	
	public inline function removeRegionContact(point:B2Contact)
	{
		if(regionContacts != null)
		{
			regionContacts.unset(point.key);
		}
	}
	
	//*-----------------------------------------------
	//* Properties
	//*-----------------------------------------------
	
	public function getID():Int
	{
		return ID;
	}
	
	public function getName():String
	{
		return name;
	}
	
	public function getGroupID():Int
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			return groupID;
		}
		
		else
		{
			return body.groupID;
		}
	}
	
	public function getLayerID():Int
	{
		return layer.ID;
	}
	
	public function getLayer():Layer
	{
		return layer;
	}
	
	public function getLayerName():String
	{
		return layer.layerName;
	}
	
	public function getLayerOrder():Int
	{
		return layer.order;
	}
	
	public function getType():ActorType
	{
		return type;
	}
		
	//*-----------------------------------------------
	//* State
	//*-----------------------------------------------
		
	public function isPausable():Bool
	{
		return getType().pausable;
	}
	
	public function isPaused():Bool
	{
		return paused;
	}
	
	public function pause()
	{
		if(isPausable())
		{
			tweenProps.pause();
			
			for (b in behaviors.behaviors)
			{
				if(b.script != null)
					b.script.pauseTweens();
			}
			
			this.paused = true;
			
			if(physicsMode == NORMAL_PHYSICS)
			{
				this.body.setPaused(true);
			}
		}
	}
	
	public function unpause()
	{
		if(isPausable())
		{
			tweenProps.unpause();
			
			for (b in behaviors.behaviors)
			{
				if(b.script != null)
					b.script.unpauseTweens();
			}
			
			this.paused = false;
			
			if(physicsMode == NORMAL_PHYSICS)
			{
				this.body.setPaused(false);
			}
		}
	}
	
	//*-----------------------------------------------
	//* Type
	//*-----------------------------------------------
	
	public function getGroup():Group
	{
		return engine.groups.get(getGroupID());
	}
	
	public function getIsRegion():Bool
	{
		return isRegion;
	}
	
	public function getIsTerrainRegion():Bool
	{
		return isTerrainRegion;
	}
	
	//*-----------------------------------------------
	//* Layering
	//*-----------------------------------------------
	
	public function moveToLayer(layer:RegularLayer)
	{
		if(!isHUD && isOfType(layer, Layer))
		{
			engine.moveActorToLayer(this, cast layer);
		}
	}
	
	public function bringToFront()
	{
		if(!isHUD)
		{
			engine.bringToFront(this);
			moveToTop();
		}
	}
	
	public function bringForward()
	{
		if(!isHUD)
		{
			engine.bringForward(this);
		}
	}
	
	public function sendToBack()
	{
		if(!isHUD)
		{
			engine.sendToBack(this);
			moveToBottom();
		}
	}
	
	public function sendBackward()
	{
		if(!isHUD)
		{
			engine.sendBackward(this);
		}
	}
	
	public function moveToBottom()
	{
		#if use_actor_tilemap
		this.parent.setTileIndex(this, 0);
		#else
		this.parent.setChildIndex(this, 0);
		#end
	}
	
	public function moveToTop()
	{
		#if use_actor_tilemap
		this.parent.setTileIndex(this, this.parent.numTiles-1);
		#else
		this.parent.setChildIndex(this, this.parent.numChildren-1);
		#end
	}
	
	public function moveDown()
	{
		#if !use_actor_tilemap
		var index:Int = this.parent.getChildIndex(this);
		if (index > 0)
		{
			this.parent.setChildIndex(this, index-1);
		}
		#else
		var index:Int = this.parent.getTileIndex(this);
		if(index > 0)
		{
			this.parent.setTileIndex(this, index-1);
		}
		#end
	}
	
	public function moveUp()
	{
		#if !use_actor_tilemap
		var index:Int = this.parent.getChildIndex(this);
		var max:Int = this.parent.numChildren-1;
		if (index < max)
		{
			this.parent.setChildIndex(this, index+1);
		}
		#else
		var index:Int = this.parent.getTileIndex(this);
		var max:Int = this.parent.numTiles-1;
		if(index < max)
		{
			this.parent.setTileIndex(this, index-1);
		}
		#end
	}
	
	public function getZIndex():Int
	{
		#if !use_actor_tilemap
		return this.parent.getChildIndex(this);
		#else
		return this.parent.getTileIndex(this);
		#end
	}
	
	public function setZIndex(zindex:Int)
	{
		#if !use_actor_tilemap
		var max:Int = this.parent.numChildren-1;
		#else
		var max:Int = this.parent.numTiles-1;
		#end
		if (zindex > max)
		{
			zindex = max;
		}
		if (zindex < 0)
		{
			zindex = 0;
		}
		#if !use_actor_tilemap
		this.parent.setChildIndex(this, zindex);
		#else
		this.parent.setTileIndex(this, zindex);
		#end
	}
	
	//*-----------------------------------------------
	//* Physics: Position
	//*-----------------------------------------------
	
	public function enableSmoothMotion()
	{
		smoothMove = true;
	}
	
	//Big Change: Returns relative to the origin point as (0,0). Meaning if the origin = center, the center is now (0,0)!
	
	public function getX(round:Bool = true):Float
	{
		var toReturn:Float = -1;
		
		if(!Engine.NO_PHYSICS)
		{
			if(isRegion || isTerrainRegion)
			{
				toReturn = Engine.toPixelUnits(body.getPosition().x) - cacheWidth/2;
			}
			
			else if(physicsMode == NORMAL_PHYSICS)
			{
				toReturn = body.getPosition().x * Engine.physicsScale - Math.floor(cacheWidth / 2) - currOffset.x;
			}
		}
		
		if (Engine.NO_PHYSICS || physicsMode != NORMAL_PHYSICS)
		{
			toReturn = realX - Math.floor(cacheWidth/2) - currOffset.x;
		}
		
		return round ? Math.round(toReturn) : toReturn;
	}
	
	public function getY(round:Bool = true):Float
	{
		var toReturn:Float = -1;
		
		if(!Engine.NO_PHYSICS)
		{
			if(isRegion || isTerrainRegion)
			{				
				toReturn = Engine.toPixelUnits(body.getPosition().y) - cacheHeight/2;
			}
			
			else if(physicsMode == NORMAL_PHYSICS)
			{
				toReturn = body.getPosition().y * Engine.physicsScale - Math.floor(cacheHeight / 2) - currOffset.y;
			}
		}
		
		if (Engine.NO_PHYSICS || physicsMode != NORMAL_PHYSICS)
		{
			toReturn = realY - Math.floor(cacheHeight / 2) - currOffset.y;
		}
		
		return round ? Math.round(toReturn) : toReturn;
	}
	
	public function getXCenter():Float
	{
		if(physicsMode == NORMAL_PHYSICS)
		{
			return Math.round(Engine.toPixelUnits(body.getWorldCenter().x) - currOffset.x);
		}
		
		else
		{
			return realX - currOffset.x;
		}
	}
	
	public function getYCenter():Float
	{
		if(physicsMode == NORMAL_PHYSICS)
		{
			return Math.round(Engine.toPixelUnits(body.getWorldCenter().y) - currOffset.y);
		}
		
		else
		{
			return realY - currOffset.y;
		}
	}
	
	public function getScreenX():Float
	{
		if(isHUD)
		{
			return getX(true);
		}
		
		else
		{
			return getX(true) - Engine.cameraX / Engine.SCALE;
		}
	}
	
	public function getScreenY():Float
	{
		if(isHUD)
		{
			return getY(true);
		}
			
		else
		{
			return getY(true) - Engine.cameraY / Engine.SCALE;
		}
	}
	
	public function setX(x:Float, resetSpeed:Bool = false, noCollision:Bool = false)
	{	
		if(physicsMode == SIMPLE_PHYSICS)
		{
			moveActorTo(x + Math.floor(cacheWidth/2) + currOffset.x, realY, noCollision || !continuousCollision);
		}
		
		else if(physicsMode == MINIMAL_PHYSICS)
		{
			resetReal(x + Math.floor(cacheWidth/2) + currOffset.x, realY);
		}
		
		else
		{
			if(isRegion || isTerrainRegion)
			{
				dummy.x = Engine.toPhysicalUnits(x);
			}
				
			else
			{
				dummy.x = Engine.toPhysicalUnits(x + Math.floor(cacheWidth/2) + currOffset.x);
			}			
			
			dummy.y = body.getPosition().y;
			
			body.setPosition(dummy);
			
			if(resetSpeed)
			{
				body.setLinearVelocity(zero);
			}
		}
		
		if (snapOnSet)
		{
			drawX = realX;
			drawY = realY;
		}
		
		updateMatrix = true;
	}
	
	public function setY(y:Float, resetSpeed:Bool = false, noCollision:Bool = false)
	{		
		if(physicsMode == SIMPLE_PHYSICS)
		{
			moveActorTo(realX, y + Math.floor(cacheHeight/2) + currOffset.y, noCollision || !continuousCollision);
		}
		
		else if(physicsMode == MINIMAL_PHYSICS)
		{
			resetReal(realX, y + Math.floor(cacheHeight/2) + currOffset.y);
		}
		
		else
		{	
			if(isRegion || isTerrainRegion)
			{
				dummy.y = Engine.toPhysicalUnits(y);
			}
				
			else
			{
				dummy.y = Engine.toPhysicalUnits(y + Math.floor(cacheHeight/2) + currOffset.y);
			}
			
			dummy.x = body.getPosition().x;
			
			body.setPosition(dummy);		
			
			if(resetSpeed)
			{
				body.setLinearVelocity(zero);
			}
		}
		
		if (snapOnSet)
		{
			drawX = realX;
			drawY = realY;
		}
		
		updateMatrix = true;
	}
	public function setXY(x:Float, y:Float, resetSpeed:Bool = false, noCollision:Bool = false)
	{
		if(physicsMode == SIMPLE_PHYSICS)
		{
			moveActorTo(
				x + Math.floor(cacheWidth/2) + currOffset.x,
				y + Math.floor(cacheHeight/2) + currOffset.y,
				noCollision || !continuousCollision);
				
			if (colX == 0 && colY == 0)
			{
				// fix for http://community.stencyl.com/index.php?issue=1506.0
				resetReal(realX, realY);
			}
		}
		
		else if(physicsMode == MINIMAL_PHYSICS)
		{
			resetReal(x + Math.floor(cacheWidth/2) + currOffset.x, y + Math.floor(cacheHeight/2) + currOffset.y);
		}
		
		else
		{	
			if(isRegion || isTerrainRegion)
			{
				dummy.x = Engine.toPhysicalUnits(x);
				dummy.y = Engine.toPhysicalUnits(y);
			}
				
			else
			{
				dummy.x = Engine.toPhysicalUnits(x + Math.floor(cacheWidth/2) + currOffset.x);
				dummy.y = Engine.toPhysicalUnits(y + Math.floor(cacheHeight/2) + currOffset.y);
			}
			
			body.setPosition(dummy);		
			
			if(resetSpeed)
			{
				body.setLinearVelocity(zero);
			}
		}
		
		if (snapOnSet)
		{
			drawX = realX;
			drawY = realY;
		}
		
		updateMatrix = true;
	}
	
	public function setXCenter(x:Float)
	{
		setX(x - (getWidth() / 2));
	}
	
	public function setYCenter(y:Float)
	{
		setY(y - (getHeight() / 2));
	}
	
	public function setScreenX(x:Float)
	{
		if(isHUD)
		{
			setX(x);
		}
		else
		{
			setX(x + (Engine.cameraX / Engine.SCALE));
		}
	}
	
	public function setScreenY(y:Float)
	{
		if(isHUD)
		{
			setY(y);
		}
		else
		{
			setY(y + (Engine.cameraY / Engine.SCALE));
		}
	}
	
	public function follow(a:Actor)
	{
		if(a == null)
		{
			return;
		}
	
		if(physicsMode != NORMAL_PHYSICS)
		{
			moveActorTo(a.getXCenter(), a.getYCenter());	
			return;
		}
		
		body.setPosition(a.body.getWorldCenter());
	}
	
	public function followWithOffset(a:Actor, ox:Int, oy:Int)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			moveActorTo(a.getXCenter() + ox, a.getYCenter() + oy);
			return;
		}
		
		var pt:B2Vec2 = a.body.getWorldCenter();
		
		pt.x += Engine.toPhysicalUnits(ox);
		pt.y += Engine.toPhysicalUnits(oy);
		
		body.setPosition(pt);
	}
	
	public function setOriginPoint(x:Int, y:Int) //logical coords
	{
		var resetPosition:B2Vec2 = null; //physical coords
		
		if (physicsMode == NORMAL_PHYSICS)
		{
			resetPosition = body.getPosition();
		}
		
		else
		{
			resetPosition = new B2Vec2(Engine.toPhysicalUnits(realX), Engine.toPhysicalUnits(realY));
		}
		
		var offsetDiff:B2Vec2 = new B2Vec2(currOffset.x, currOffset.y); //logical coords
		var radians:Float = getAngle();
			
		var rotated:Bool = Std.int(radians * Utils.DEG) != 0;	
		
		var w:Float = cacheWidth;
		var h:Float = cacheHeight;
		
		var newOffX:Int = Std.int(x - (w / 2));
		var newOffY:Int = Std.int(y - (h / 2));
				
		if (currOrigin != null && (Std.int(currOffset.x) != newOffX || Std.int(currOffset.y) != newOffY) && rotated)
		{
			var oldAng:Float = radians + Math.atan2( -currOffset.y, -currOffset.x);
			var newAng:Float = radians + Math.atan2( -newOffY, -newOffX);			
			var oldDist:Float = Math.sqrt(Math.pow(currOffset.x, 2) + Math.pow(currOffset.y, 2));
			var newDist:Float = Math.sqrt(Math.pow(newOffX, 2) + Math.pow(newOffY, 2));
							
			var oldFixCenterX:Int = Math.round(currOrigin.x + Math.cos(oldAng) * oldDist);
			var oldFixCenterY:Int = Math.round(currOrigin.y + Math.sin(oldAng) * oldDist);
			var newFixCenterX:Int = Math.round(x + Math.cos(newAng) * newDist);
			var newFixCenterY:Int = Math.round(y + Math.sin(newAng) * newDist);
					
			resetPosition.x += Engine.toPhysicalUnits(oldFixCenterX - newFixCenterX);
			resetPosition.y += Engine.toPhysicalUnits(oldFixCenterY - newFixCenterY);
		}
		
		currOrigin.x = x;
		currOrigin.y = y;
		currOffset.x = newOffX;
		currOffset.y = newOffY;
							
		offsetDiff.x = currOffset.x - offsetDiff.x;
		offsetDiff.y = currOffset.y - offsetDiff.y;		
					
		resetPosition.x += Engine.toPhysicalUnits(offsetDiff.x);
		resetPosition.y += Engine.toPhysicalUnits(offsetDiff.y);
		
		if(physicsMode == NORMAL_PHYSICS)
		{
			body.setPosition(resetPosition);
		}
		
		else
		{
			realX = Engine.toPixelUnits(resetPosition.x);
			realY = Engine.toPixelUnits(resetPosition.y);
		}
		
		resetOrigin = true;
	}
	
	//*-----------------------------------------------
	//* Physics: Velocity
	//*-----------------------------------------------
	
	public function getXVelocity():Float
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			return xSpeed;
		}
		
		return body.getLinearVelocity().x;
	}
	
	public function getYVelocity():Float
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			return ySpeed;
		}
		
		return body.getLinearVelocity().y;
	}
	
	public function setXVelocity(dx:Float)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			xSpeed = dx;
			return;
		}
		
		var v = body.getLinearVelocity();
		v.x = dx;
		body.setLinearVelocity(v);
		body.setAwake(true);
	}
	
	public function setYVelocity(dy:Float)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			ySpeed = dy;
			return;
		}
		
		var v = body.getLinearVelocity();
		v.y = dy;
		body.setLinearVelocity(v);
		body.setAwake(true);
	}
	
	public function setVelocity(angle:Float, speed:Float)
	{
		setXVelocity(speed * Math.cos(Utils.RAD * angle));
		setYVelocity(speed * Math.sin(Utils.RAD * angle));
	}
	
	public function accelerateX(dx:Float)
	{
		setXVelocity(getXVelocity() + dx);
	}
	
	public function accelerateY(dy:Float)
	{
		setYVelocity(getYVelocity() + dy);
	}
	
	public function accelerate(angle:Float, speed:Float)
	{
		setXVelocity(getXVelocity() + speed * Math.cos(Utils.RAD * angle));
		setYVelocity(getYVelocity() + speed * Math.sin(Utils.RAD * angle));
	}
	
	//*-----------------------------------------------
	//* Physics: Angles and Angular Velocity
	//*-----------------------------------------------
	
	public function getAngle():Float
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			return Utils.RAD * realAngle;
		}
		
		return body.getAngle();
	}
	
	public function getAngleInDegrees():Float
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			return realAngle;
		}
		
		return Utils.DEG * body.getAngle();
	}
	
	public function setAngle(angle:Float, inRadians:Bool = true)
	{
		if(inRadians)
		{
			if(physicsMode != NORMAL_PHYSICS)
			{
				realAngle = Utils.DEG * angle;
			}
			
			else
			{
				body.setAngle(angle);				
			}
		}
		
		else
		{
			if(physicsMode != NORMAL_PHYSICS)
			{
				realAngle = angle;
			}
			
			else
			{
				body.setAngle(Utils.RAD * angle);		
			}
		}
		
		updateMatrix = true;
	}
	
	public function rotate(angle:Float, inRadians:Bool = true)
	{
		if(inRadians)
		{
			if(physicsMode != NORMAL_PHYSICS)
			{
				realAngle += Utils.DEG * angle;
			}
			
			else
			{
				body.setAngle(body.getAngle() + angle);
			}
		}
			
		else
		{
			if(physicsMode != NORMAL_PHYSICS)
			{
				realAngle += angle;
			}
			
			else
			{
				body.setAngle(body.getAngle() + (Utils.RAD * angle));
			}	
		}
	}
	
	public function getAngularVelocity():Float
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			return Utils.RAD * rSpeed;
		}
		
		return body.getAngularVelocity();
	}
	
	public function setAngularVelocity(omega:Float)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			rSpeed = Utils.DEG * omega;
		}
		
		else
		{
			body.setAngularVelocity(omega);	
			body.setAwake(true);
		}
	}
	
	public function changeAngularVelocity(omega:Float)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			rSpeed += Utils.DEG * omega;
		}
		
		else
		{
			body.setAngularVelocity(body.getAngularVelocity() + omega);
			body.setAwake(true);
		}
	}
	
	//*-----------------------------------------------
	//* Physics: Forces
	//*-----------------------------------------------
	
	public function push(dirX:Float, dirY:Float, magnitude:Float)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			dummy.x = dirX;
			dummy.y = dirY;
			dummy.normalize();
		
			accelerateX(dummy.x * magnitude * 0.01);
			accelerateY(dummy.y * magnitude * 0.01);
			return;
		}
		
		if(dirX == 0 && dirY == 0)
		{
			return;
		}
		
		dummy.x = dirX;
		dummy.y = dirY;
		dummy.normalize();
		dummy.multiply(magnitude);
		
		body.applyForce(dummy, body.getWorldCenter());
	}
	
	//in degrees
	public function pushInDirection(angle:Float, speed:Float)
	{
		push
		(
			Math.cos(Utils.RAD * angle),
			Math.sin(Utils.RAD * angle),
			speed
		);
	}
	
	public function applyImpulse(dirX:Float, dirY:Float, magnitude:Float)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			dummy.x = dirX;
			dummy.y = dirY;
			dummy.normalize();
		
			//TODO: Figure out how to match Box2D
			accelerateX(dummy.x * magnitude);
			accelerateY(dummy.y * magnitude);
			//accelerateX(dummy.x * magnitude * 8);
			//accelerateY(dummy.y * magnitude * 8);
			return;
		}
		
		if(dirX == 0 && dirY == 0)
		{
			return;
		}
		
		dummy.x = dirX;
		dummy.y = dirY;
		dummy.normalize();
		dummy.multiply(magnitude);
		
		body.applyImpulse(dummy, body.getWorldCenter());
	}
	
	//in degrees
	public function applyImpulseInDirection(angle:Float, speed:Float)
	{
		applyImpulse
		(
			Math.cos(Utils.RAD * angle),
			Math.sin(Utils.RAD * angle),
			speed
		);
	}
	
	public function applyTorque(torque:Float)
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			if(!fixedRotation)
			{
				rSpeed -= torque;
			}
		}
		
		else
		{
			body.applyTorque(torque);
			body.setAwake(true);
		}
	}
	
	//*-----------------------------------------------
	//* Size
	//*-----------------------------------------------
	
	public function getWidth():Float
	{
		return cacheWidth;
	}
	
	public function getHeight():Float
	{
		return cacheHeight;
	}
	
	public function getPhysicsWidth():Float
	{
		return cacheWidth / Engine.physicsScale;
	}
	
	public function getPhysicsHeight():Float
	{
		return cacheHeight / Engine.physicsScale;
	}
	
	//*-----------------------------------------------
	//* Physics Flags
	//*-----------------------------------------------
	
	public function getBody():B2Body
	{
		return body;
	}
	
	public function enableRotation()
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			fixedRotation = false;
		}
		
		else
		{
			body.setFixedRotation(false);
		}
	}
	
	public function disableRotation()
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			fixedRotation = true;
		}
		
		else
		{
			body.setFixedRotation(true);
		}
	}
	
	public function setIgnoreGravity(state:Bool)
	{
		ignoreGravity = state;
	
		if(physicsMode == NORMAL_PHYSICS)
		{
			body.setIgnoreGravity(state);
		}
	}
	
	public function ignoresGravity():Bool
	{
		if(physicsMode != NORMAL_PHYSICS)
		{
			return ignoreGravity;
		}
		
		return body.isIgnoringGravity();
	}
	
	public function getFriction():Float
	{
		if (physicsMode == NORMAL_PHYSICS && body.m_fixtureList != null)
		{
			return body.m_fixtureList.m_friction;
		}
		
		return 0;
	}
	
	public function getBounciness():Float
	{
		if (physicsMode == NORMAL_PHYSICS && body.m_fixtureList != null)
		{
			return body.m_fixtureList.m_restitution;
		}
		
		return 0;
	}
	
	public function getMass():Float
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			return md.mass;
		}
		
		return 0;
	}
	
	public function getAngularMass():Float
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			return md.I;
		}
		
		return 0;
	}
	
	public function getLinearDamping():Float
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			return body.getLinearDamping();
		}
		
		return 0;
	}
	
	public function getAngularDamping():Float
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			return body.getAngularDamping();
		}
		
		return 0;
	}
	
	public function setFriction(value:Float)
	{
		if(physicsMode == NORMAL_PHYSICS)
		{
			body.setFriction(value);
		}
	}
	
	public function setBounciness(value:Float)
	{
		if(physicsMode == NORMAL_PHYSICS)
		{
			body.setBounciness(value);
		}
	}
	
	public function setMass(newMass:Float)
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			md.mass = newMass;
			body.setMassData(this.md);
		}
	}
	
	public function setAngularMass(newAMass:Float)
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			md.I = newAMass;
			body.setMassData(this.md);
		}
	}
	
	public function setLinearDamping(newDamping:Float)
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			body.setLinearDamping(newDamping);
		}
	}
	
	public function setAngularDamping(newDamping:Float)
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			body.setAngularDamping(newDamping);
		}
	}
	
	//*-----------------------------------------------
	//* Mouse Convenience
	//*-----------------------------------------------
	
	public function isMouseOver():Bool
	{
		var mx:Float;
		var my:Float;
		
		if(isHUD)
		{
			mx = (Input.mouseX - Engine.engine.hudLayer.x) / Engine.SCALE;
		 	my = (Input.mouseY - Engine.engine.hudLayer.y) / Engine.SCALE;
		}
		
		else
		{
			mx = (Input.mouseX + Engine.cameraX * layer.scrollFactorX) / Engine.SCALE;
		 	my = (Input.mouseY + Engine.cameraY * layer.scrollFactorY) / Engine.SCALE;
		}
		
		//TODO: Mike - Make this work with arbitrary origin points
		//The problem was that mouse detect was off for higher scales
		//and would only work within the centered, original bounds.
		var scaleXAbs = Math.abs(realScaleX);
		var scaleYAbs = Math.abs(realScaleY);
		var offsetLeft = currOrigin.x * (scaleXAbs - 1);
		var offsetRight = (cacheWidth - currOrigin.x) * (scaleXAbs - 1);
		var offsetUp = currOrigin.y * (scaleYAbs - 1);
		var offsetDown = (cacheHeight - currOrigin.y) * (scaleYAbs - 1);
		
		// Added to fix this issue -- http://community.stencyl.com/index.php?issue=488.0
		if(physicsMode != NORMAL_PHYSICS)
		{
			// Check if the origin point is something other than center.
			if((currOrigin.x != cacheWidth / 2) || (currOrigin.y != cacheHeight / 2))
			{
				resetReal(realX, realY);
			}
		}
		
		var xPos = colX - offsetLeft;
		var yPos = colY - offsetUp;

		if(rotation != 0)
		{
			// Imagine a circle with the actor's origin point as the center and the mouse position somewhere on the circle.
			// If the circle is rotated by the actor's direction, then the mouse's new position can be compared with the actor's original bounding box.
			var actorOriginX:Float = xPos + currOrigin.x * scaleXAbs;
			var actorOriginY:Float = yPos + currOrigin.y * scaleYAbs;
			var xFromOrigin:Float = mx - actorOriginX;
			var yFromOrigin:Float = my - actorOriginY;
			var rotationRadians:Float = Utils.RAD * rotation;
			var mxNew:Float = actorOriginX + (xFromOrigin * Math.cos(rotationRadians)) + (yFromOrigin * Math.sin(rotationRadians));
			var myNew:Float = actorOriginY - (xFromOrigin * Math.sin(rotationRadians)) + (yFromOrigin * Math.cos(rotationRadians));
			mx = mxNew;
			my = myNew;
		}

                if(isHUD && !Engine.engine.isHUDZoomable)
		{
			return (mx >= xPos/Engine.engine.zoomMultiplier && 
		   		my >= yPos/Engine.engine.zoomMultiplier && 
		   		mx < (xPos + cacheWidth + offsetLeft + offsetRight)/Engine.engine.zoomMultiplier && 
		   		my < (yPos + cacheHeight + offsetUp + offsetDown)/Engine.engine.zoomMultiplier);	
		}
		else
		{
			return (mx >= xPos && 
			   		my >= yPos && 
			   		mx < xPos + cacheWidth + offsetLeft + offsetRight && 
			   		my < yPos + cacheHeight + offsetUp + offsetDown);
		}
	}
	
	public function isMouseHover():Bool
	{
		return isMouseOver() && !Input.mouseDown;
	}
	
	public function isMouseDown():Bool
	{
		return isMouseOver() && Input.mouseDown;
	}
	
	public function isMousePressed():Bool
	{
		return isMouseOver() && Input.mousePressed;
	}
	
	public function isMouseReleased():Bool
	{
		return isMouseOver() && Input.mouseReleased;
	}
	
	//*-----------------------------------------------
	//* Tween Convenience
	//*-----------------------------------------------
	
	public function cancelTweens()
	{
		tweenProps.cancel();
	}

	public function fadeTo(value:Float, duration:Float = 1, easing:EasingFunction = null)
	{
		tweenProps.alpha.tween(alpha, value, easing, Std.int(duration*1000));
	}
	
	public function growTo(scaleX:Float = 1, scaleY:Float = 1, duration:Float = 1, easing:EasingFunction = null)
	{
		tweenProps.realScaleXY.tween(realScaleX, scaleX, realScaleY, scaleY, easing, Std.int(duration*1000));
	}
	
	//In degrees
	public function spinTo(angle:Float, duration:Float = 1, easing:EasingFunction = null)
	{
		tweenProps.angle.tween(getAngleInDegrees(), angle, easing, Std.int(duration*1000));
	}
	
	public function moveTo(x:Float, y:Float, duration:Float = 1, easing:EasingFunction = null)
	{
		tweenProps.xy.tween(getX(false), x, getY(false), y, easing, Std.int(duration*1000));
	}
	
	//In degrees
	public function spinBy(angle:Float, duration:Float = 1, easing:EasingFunction = null)
	{
		spinTo(getAngleInDegrees() + angle, duration, easing);
	}
	
	public function moveBy(x:Float, y:Float, duration:Float = 1, easing:EasingFunction = null)
	{		
		moveTo(getX(false) + x, getY(false) + y, duration, easing);
	}
	
	
	//*-----------------------------------------------
	//* Drawing
	//*-----------------------------------------------
	
	public function drawImage(g:G)
	{
		if(currAnimation != null)
		{
			var x:Float = 0;
			var y:Float = 0;
			
			#if use_actor_tilemap
			if(g.drawActor)
			{
				x = g.x - Engine.cameraX;
				y = g.y - Engine.cameraY;
			}
			
			else
			{
				x = g.x;
				y = g.y;
			}
			#end		
			
			//TODO: See if I can make more efficient
			if (realAngle > 0)
			{
				drawMatrix.identity();
				transformPoint.x = (0 - cacheWidth / 2) * Engine.SCALE;
				transformPoint.y = (0 - cacheHeight / 2) * Engine.SCALE;

				drawMatrix.translate( -transformPoint.x, -transformPoint.y);
				drawMatrix.scale(realScaleX, realScaleY);		
				drawMatrix.rotate(realAngle * Utils.RAD);		
		
				drawMatrix.translate(colX * Engine.SCALE, colY * Engine.SCALE);
				
				x += transformMatrix.tx - drawMatrix.tx;
				y += transformMatrix.ty - drawMatrix.ty;
			}
			
			var visibleCache = currAnimation.visible;
			currAnimation.visible = true;
			currAnimation.draw(g, x, y, realAngle * Utils.RAD, g.alpha);
			currAnimation.visible = visibleCache;
		}
	}
	
	public function getCurrentImage()
	{
		return currAnimation.getCurrentImage();
	}
	
	public function enableActorDrawing()
	{
		drawActor = true;
		
		if(currAnimation != null)
		{
			currAnimation.visible = true;
		}
	}
	
	public function disableActorDrawing()
	{
		drawActor = false;
		
		if(currAnimation != null)
		{
			currAnimation.visible = false;
		}
	}
	
	public function drawsImage():Bool
	{
		return drawActor;
	}
	
	//*-----------------------------------------------
	//* Filters
	//*-----------------------------------------------

	public function setFilter(filter:Array<BitmapFilter>)
	{
		if(bitmapFilters == null)
			bitmapFilters = [];
		bitmapFilters = bitmapFilters.concat(filter);
		#if (flash || canvas)
			if(currAnimation != null)
				currAnimation.filter = bitmapFilters;
		#else
			usingSoftwareFilter = Lambda.exists(bitmapFilters, function(f) {return !Std.is(f, ColorMatrixFilter);});

			if(!usingSoftwareFilter)
			{
				var cm = new ColorMatrix();
				var first = true;
				for(f in bitmapFilters)
				{
					var cmf = cast(f, ColorMatrixFilter);
					if(first)
					{
						cm.setArray(cmf.matrix);
						first = false;
					}
					else
					{
						var cm2 = new ColorMatrix();
						cm2.setArray(cmf.matrix);
						var cm3 = new ColorMatrix();
						
						//original color is on the right in the final
						//multiplication, so additional matrices should
						//be added to the left
						ColorMatrix.mulMatrixMatrix(cm2, cm, cm3);
						cm3.toArray(cm3.matrix);
						cm = cm3;
					}
				}
				var cms = new ColorMatrixShader();
				cms.init(cm.matrix);
				filtersAsShader = cms;
			}
			else
			{
				filtersAsShader = null;
			}
			
			if(usingSoftwareFilter)
			{
				#if use_actor_tilemap
				Log.error("software filters not implemented");
				#else
				if(currAnimation != null)
					currAnimation.filter = bitmapFilters;
				#end
			}
			currAnimation.shader = filtersAsShader;
		#end
	}
	
	public function clearFilters()
	{
		bitmapFilters = null;
		#if (flash || canvas)
			if(currAnimation != null)
				currAnimation.filter = null;
		#else
			usingSoftwareFilter = false;
			filtersAsShader = null;
			#if !use_actor_tilemap
			if(currAnimation != null)
				currAnimation.filter = null;
			#end
			currAnimation.shader = null;
		#end
	}
	
	public function setBlendMode(blendMode:BlendMode)
	{
		this.blendMode = blendMode;
	}
	
	public function resetBlendMode()
	{
		this.blendMode = BlendMode.NORMAL;
	}
	
	//*-----------------------------------------------
	//* Behaviors
	//*-----------------------------------------------
	
	public function addBehavior(b:Behavior)
	{
		if(behaviors != null)
		{
			behaviors.add(b);
		}
	}
	
	public function hasBehavior(name:String):Bool
	{
		if(behaviors != null)
		{
			return behaviors.hasBehavior(name);
		}
		
		return false;
	}
	
	public function enableBehavior(name:String)
	{
		if(behaviors != null)
		{
			behaviors.enableBehavior(name);
		}
	}
	
	public function disableBehavior(name:String)
	{
		if(behaviors != null)
		{
			behaviors.disableBehavior(name);
		}
	}
	
	public function isBehaviorEnabled(name:String):Bool
	{
		if(behaviors != null)
		{
			return behaviors.isBehaviorEnabled(name);
		}
		
		return false;
	}
	
	public function enableAllBehaviors()
	{
		if(behaviors != null)
		{
			for(b in behaviors.behaviors)
			{
				b.enabled = true;
			}
		}
	}
		
	//*-----------------------------------------------
	//* Messaging
	//*-----------------------------------------------
	
	public function getValue(behaviorName:String, attributeName:String):Dynamic
	{
		return behaviors.getAttribute(behaviorName, attributeName);
	}
	
	public function setValue(behaviorName:String, attributeName:String, value:Dynamic)
	{
		behaviors.setAttribute(behaviorName, attributeName, value);
	}
	
	public function shout(msg:String, args:Array<Dynamic> = null):Dynamic
	{
		return behaviors.call(msg, args);
	}
	
	public function say(behaviorName:String, msg:String, args:Array<Dynamic> = null):Dynamic
	{
		return behaviors.call2(behaviorName, msg, args);
	}
	
	//*-----------------------------------------------
	//* Actor-Level Attributes
	//*-----------------------------------------------
	
	public function setActorValue(name:String, value:Dynamic)
	{
		if(registry != null)
		{
			registry.set(name, value);
		}
	}
	
	public function getActorValue(name:String):Dynamic
	{
		if(registry == null)
		{
			return null;
		}
		
		else
		{
			return registry.get(name);
		}
	}
	
	public function hasActorValue(name:String):Dynamic
	{
		if(registry == null)
		{
			return null;
		}
		
		return registry.get(name) != null;
	}
	
	//*-----------------------------------------------
	//* Events Plumbing
	//*-----------------------------------------------
	
	public function registerListener(type:Event<Dynamic>, listener:Dynamic)
	{
		var ePos:Int = Utils.indexOf(allEventReferences, type);
		
		var listenerList:Array<Dynamic> = null; 
		
		if (ePos != -1)
		{
			listenerList = allListeners.get(ePos);
		}
		
		else
		{
			allEventReferences.push(type);
			ePos = allEventReferences.length - 1;
			
			listenerList = new Array<Dynamic>();
			allListeners.set(ePos, listenerList);
		}
		
		listenerList.push(listener);
	}
	
	public function removeAllListeners()
	{			
		for(k in 0...allEventReferences.length)
		{
			var event:Event<Dynamic> = allEventReferences[k];
			
			if(event != null)
			{
				var list:Array<Dynamic> = cast(allListeners.get(k), Array<Dynamic>);
				
				if(list != null)
				{
					for(r in 0...list.length)
					{
						event.remove(list[r]);
					}
				}
			}
		}
		
		Utils.clear(allEventReferences);
	}	
	
	//*-----------------------------------------------
	//* Misc
	//*-----------------------------------------------	
	
	public function anchorToScreen()
	{
		if(isHUD)
			return;
		
		engine.moveActorToLayer(this, engine.hudLayer);
	}
	
	public function unanchorFromScreen()
	{
		if(!isHUD)
			return;
		
		engine.moveActorToLayer(this, cachedLayer);
	}
	
	public function isAnchoredToScreen():Bool
	{
		return isHUD;
	}
	
	public function makeAlwaysSimulate(alterBody:Bool = true)
	{
		if (!alwaysSimulate)
		{
			if(physicsMode == NORMAL_PHYSICS && alterBody)
			{
				body.setAlwaysActive(true);
				body.setActive(true);
			}
			
			alwaysSimulate = true;
		}
	}
	
	public function makeSometimesSimulate(alterBody:Bool = true)
	{
		if (alwaysSimulate)
		{
			if(physicsMode == NORMAL_PHYSICS && alterBody)
			{
				body.setAlwaysActive(false);
				body.setActive(false);
			}
			
			alwaysSimulate = false;
		}
	}
	
	public function alwaysSimulates():Bool
	{
		return alwaysSimulate;
	}
	
	public function die()
	{
		dying = true;
		
		var a = engine.whenTypeGroupKilledEvents.get(typeID);
		var b = engine.whenTypeGroupKilledEvents.get(groupID + Actor.GROUP_OFFSET);
	
		whenKilled.dispatch();

		if(a != null)
		{
			a.dispatch(this);
		}
		
		if(b != null)
		{
			b.dispatch(this);
		}
		
		removeAllListeners();
	}
		
	public function isDying():Bool
	{
		return dying;
	}
	
	public function isAlive():Bool
	{
		return !(dead || dying || recycled);
	}

	//hand-inlined to engine to avoid overhead
	public function isOnScreen():Bool
	{
		var cameraX = Engine.cameraX / Engine.SCALE;
		var cameraY = Engine.cameraY / Engine.SCALE;
		
		var left = Engine.paddingLeft;
		var top = Engine.paddingTop;
		var right = Engine.paddingRight;
		var bottom = Engine.paddingBottom;
	
		return (physicsMode != NORMAL_PHYSICS || body.isActive()) && 
			   getX(true) + cacheWidth * realScaleX >= cameraX - left && 
			   getY(true) + cacheHeight * realScaleY >= cameraY - top &&
			   getX(true) < cameraX + Engine.screenWidth + right &&
			   getY(true) < cameraY + Engine.screenHeight + bottom;
	}
	
	public function isInScene():Bool
	{
		return (physicsMode != NORMAL_PHYSICS || body.isActive()) && 
			   getX(true) + cacheWidth * realScaleX >= 0 && 
			   getY(true) + cacheHeight * realScaleY >= 0 &&
			   getX(true) < Engine.sceneWidth &&
			   getY(true) < Engine.sceneHeight;
	}
	
	public function getLastCollidedActor():Actor
	{
		return Actor.lastCollided;
	}
	

	//Kills this actor after it leaves the screen
	public function killSelfAfterLeavingScreen()
	{
		killLeaveScreen = true;
	}
	
	#if !use_actor_tilemap override #end public function toString():String
	{
		if(name == null)
		{
			return "Unknown Actor " + ID;
		}
		
		return "[Actor " + ID + "," + name + "]";
	}
	
	public static function scaleShape(shape:B2Shape, center:B2Vec2, factor:Float)
	{
		if(isOfType(shape, B2CircleShape))
		{
			var circle:B2CircleShape = cast shape;
			
			circle.m_radius *= factor;
		}
		
		else if(isOfType(shape, B2PolygonShape))
		{
			var polygon:B2PolygonShape = cast shape;
			var vertices:Array<B2Vec2> = polygon.m_vertices;
			var newVertices:Array<B2Vec2> = new Array<B2Vec2>();
			
			for (v in vertices)
			{
				v.subtract(center);
				v.multiply(factor);
				v.add(center);
				newVertices.push(v);
			}
			
			polygon.setAsArray(newVertices);
		}
	}
	
	public function addRectangularShape(x:Float, y:Float, w:Float, h:Float)
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			var polygon:B2PolygonShape = new B2PolygonShape();
			var vertices:Array<B2Vec2> = new Array<B2Vec2>();
			x = Engine.toPhysicalUnits(x - Math.floor(cacheWidth / 2) - currOffset.x);
			y = Engine.toPhysicalUnits(y - Math.floor(cacheHeight / 2) - currOffset.y);
			w = Engine.toPhysicalUnits(w);
			h = Engine.toPhysicalUnits(h);
			vertices.push(new B2Vec2(x, y));
			vertices.push(new B2Vec2(x + w, y));
			vertices.push(new B2Vec2(x + w, y + h));
			vertices.push(new B2Vec2(x, y + h));
			polygon.setAsVector(vertices);
			var fixture:B2Fixture = createFixture(polygon);
			fixture.SetUserData(this);
		}
	}
	
	public function addCircularShape(x:Float, y:Float, r:Float)
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			var circle:B2CircleShape = new B2CircleShape();
			circle.m_radius = Engine.toPhysicalUnits(r);
			circle.m_p.x = Engine.toPhysicalUnits(x);
			circle.m_p.y = Engine.toPhysicalUnits(y);
			var fixture:B2Fixture = createFixture(circle);
			fixture.SetUserData(this);
		}
	}
	
	public function addVertex(vertices:Array<B2Vec2>, x:Float, y:Float)
	{
		x = Engine.toPhysicalUnits(x - Math.floor(cacheWidth / 2) - currOffset.x);
		y = Engine.toPhysicalUnits(y - Math.floor(cacheHeight / 2) - currOffset.y);
		vertices.push(new B2Vec2(x, y));
	}
	
	public function addPolygonalShape(vertices:Array<B2Vec2>)
	{
		if (physicsMode == NORMAL_PHYSICS)
		{
			var polygon:B2PolygonShape = new B2PolygonShape();
			/*var newVertices:Array<B2Vec2> = new Array<B2Vec2>();
			for (v in vertices)
			{
				v.subtract(new B2Vec2(getPhysicsWidth()/2, getPhysicsHeight()/2));
				newVertices.push(v);
			}
			polygon.setAsArray(newVertices);*/
			polygon.setAsArray(vertices);
			var fixture:B2Fixture = createFixture(polygon);
			fixture.SetUserData(this);
		}
	}

	public function createFixture(newShape:B2Shape):B2Fixture
	{
		var def:B2FixtureDef = new B2FixtureDef();
		def.shape = newShape;
		def.density = bodyDef.mass * 0.1;
		def.friction = bodyDef.friction;
		def.restitution = bodyDef.bounciness;
		return body.createFixture(def);
	}
	
	public function getLastCreatedFixture():B2Fixture
	{
		if(physicsMode == NORMAL_PHYSICS)
		{
			return body.getFixtureList();
		}
		return null;
	}
	
	//*-----------------------------------------------
	//* Camera-Only
	//*-----------------------------------------------
	
	public function setLocation(x:Float, y:Float)
	{			
		realX = x;
		realY = y;
		
		setXY(x, y, false, true);
	}
	
	//*-----------------------------------------------
	//* Simple Collision system (via FlashPunk)
	//*-----------------------------------------------

	/**
	 * An optional Mask component, used for specialized collision. If this is
	 * not assigned, collision checks will use the Entity's hitbox by default.
	 */
	public var shape(get, set):Mask;
	private inline function get_shape():Mask { return _mask; }
	private function set_shape(value:Mask):Mask
	{
		if (_mask == value) return value;
		if (_mask != null) _mask.assignTo(null);
		_mask = value;
		if (value != null) _mask.assignTo(this);
		return _mask;
	}
	
	/**
	 * Checks for a collision against an Entity type.
	 * @param	type		The Entity type to check for.
	 * @param	x			Virtual x position to place this Entity.
	 * @param	y			Virtual y position to place this Entity.
	 * @return	The first Entity collided with, or null if none were collided.
	 */
	public function collide(groupID:Int, x:Float, y:Float):Actor
	{
		//Grab all actors from a group. For us, that means grabbing the group! (instead of a string type)
		var actorList = engine.getGroup(groupID);
		
		_x = realX; _y = realY;
		resetReal(x, y);

		if (_mask == null)
		{
			for(actor in actorList.list)
			{
				var e = actor;
				
				if (e.recycled)
				{
					continue;
				}
				
				if (colX + cacheWidth >= e.colX
				&& colY + cacheHeight >= e.colY
				&& colX <= e.colX + e.cacheWidth
				&& colY <= e.colY + e.cacheHeight
				&& e.collidable && e != this)
				{
					if (e._mask == null || e._mask.collide(HITBOX))
					{			
						colMask = e._mask;
						resetReal(_x, _y);						
						
						return e;
					}
				}
			}
			
			resetReal(_x, _y);			
			return null;
		}

		for(actor in actorList.list)
		{
			var e = actor;
			
			if (e.recycled)
			{
				continue;
			}
	
			if (colX + cacheWidth >= e.colX
			&& colY + cacheHeight >= e.colY
			&& colX <= e.colX + e.cacheWidth
			&& colY <= e.colY + e.cacheHeight
			&& e.collidable && e != this)
			{				
				if (_mask.collide(e._mask != null ? e._mask : e.HITBOX))
				{			
					colMask = (e._mask != null ? e._mask : e.HITBOX);
					resetReal(_x, _y);										
					
					return e;
				}
			}
		}
		resetReal(_x, _y);
		return null;
	}

	/**
	 * Checks for collision against multiple Entity types.
	 * @param	types		An Array or Vector of Entity types to check for.
	 * @param	x			Virtual x position to place this Entity.
	 * @param	y			Virtual y position to place this Entity.
	 * @return	The first Entity collided with, or null if none were collided.
	 */
	public function collideTypes(types:Array<Int>, x:Float, y:Float):Actor
	{
		var cc:Int = collidedList.length;
		
		var e:Actor;
		var type:Int;
		for (type in types)
		{
			if (type == GameModel.REGION_ID) continue;
			
			collideInto(type, x, y, collidedList);
		}
		
		if (collidedList.length > cc)
		{					
			return collidedList[collidedList.length - 1];
		}
		
		return null;
	}
	
	/**
	 * Checks if this Entity collides with a specific Entity.
	 * @param	e		The Entity to collide against.
	 * @param	x		Virtual x position to place this Entity.
	 * @param	y		Virtual y position to place this Entity.
	 * @return	The Entity if they overlap, or null if they don't.
	 */
	public function collideWith(e:Actor, x:Float, y:Float):Actor
	{
		_x = realX; _y = realY;
		resetReal(x, y);

		if (colX + cacheWidth >= e.colX
		&& colY + cacheHeight >= e.colY
		&& colX <= e.colX + e.cacheWidth
		&& colY <= e.colY + e.cacheHeight
		&& collidable && e.collidable)
		{
			if (_mask == null)
			{
				if (e._mask == null || e._mask.collide(HITBOX))
				{
					resetReal(_x, _y);
					return e;
				}
				resetReal(_x, _y);
				return null;
			}
			if (_mask.collide(e._mask != null ? e._mask : e.HITBOX))
			{
				resetReal(_x, _y);
				return e;
			}
		}
		resetReal(_x, _y);
		return null;
	}

	/**
	 * Populates an array with all collided Entities of a type.
	 * @param	type		The Entity type to check for.
	 * @param	x			Virtual x position to place this Entity.
	 * @param	y			Virtual y position to place this Entity.
	 * @param	array		The Array or Vector object to populate.
	 * @return	The array, populated with all collided Entities.
	 */
	public function collideInto(groupID:Int, x:Float, y:Float, array:Array<Actor>)
	{
		//Grab all actors from a group. For us, that means grabbing the group! (instead of a string type)
		var actorList = engine.getGroup(groupID);

		_x = realX; _y = realY;
		resetReal(x, y);
		var n:Int = array.length;

		if (_mask == null)
		{
			for(actor in actorList.list)
			{
				var e = actor;
				
				if (e.recycled)
				{
					continue;
				}
				
				if (colX + cacheWidth >= e.colX
				&& colY + cacheHeight >= e.colY
				&& colX <= e.colX + e.cacheWidth
				&& colY <= e.colY + e.cacheHeight
				&& e.collidable && e != this)
				{
					if (e._mask == null || e._mask.collide(HITBOX)) 
					{
						if (!Utils.contains(array, e))
						{
							array[n++] = e;
						}
					}
				}
			}
			resetReal(_x, _y);
			return;
		}

		for(actor in actorList.list)
		{
			var e = actor;
			
			if (colX + cacheWidth >= e.colX
			&& colY + cacheHeight >= e.colY
			&& colX <= e.colX + e.cacheWidth
			&& colY <= e.colY + e.cacheHeight
			&& e.collidable && e != this)			
			{
				if (_mask.collide(e._mask != null ? e._mask : e.HITBOX)) 
				{
					if (!Utils.contains(array, e))
					{
						array[n++] = e;
					}
				}
			};
		}
		resetReal(_x, _y);
		return;
	}
	
	public function clearCollisionInfoList()
	{
		if (collisionsCount > 0)
		{
			for(info in simpleCollisions) 
			{
				info.remove = true;		
				
				if (info.linkedCollision != null)
				{
					info.linkedCollision.remove = true;
				}
			}
		}	
	}
	
	public function disposeRemovedCollisionInfo()
	{
		if (collisionsCount > 0)
		{
			var maxKey = -1;
		
			for(key in simpleCollisions.keys()) 
			{
				var info = simpleCollisions.get(key);
				
				if(info.remove)
				{
					simpleCollisions.unset(key);
				}
				else if(key > maxKey)
				{
					maxKey = key;
				}
			}
			
			collisionsCount = maxKey + 1;
		}
	}
	
	private function clearCollidedList()
	{
		while (collidedList.length > 0)
		{
			collidedList.pop();
		}
		
		listChecked = 0;
	}
	
	public function addCollision(info:Collision):Collision
	{
		var check:Int;
		
		if ((check = alreadyCollided(info)) != -1) {
			var oldInfo:Collision = simpleCollisions.get(check);
			
			info.switchData(oldInfo.linkedCollision);
			info.linkedCollision.remove = false;
			info.remove = false;
			
			Collision.recycle(oldInfo);
			
			simpleCollisions.unset(check);
			simpleCollisions.set(check, info);
			
			return info;
		}
		
		simpleCollisions.unset(collisionsCount);
		simpleCollisions.set(collisionsCount, info);
		collisionsCount++;		
		
		return info;
	}
	
	public function alreadyCollided(info2:Collision):Int
	{
		for (key in simpleCollisions.keys())
		{
			var info:Collision = simpleCollisions.get(key);
			
			if (info != null && ((info.maskA == info2.maskA && info.maskB == info2.maskB) || (info.maskA == info2.maskB && info.maskB == info2.maskA)))			
			{
				// added to avoid up/down tile collisions from overwriting left/right tile collisions since each tile is not its own unique object
				if (info.solidCollision)
				{
					if (info.maskA.groupID == 1 || info.maskB.groupID == 1)
					{
						if (info.thisFromLeft || info.thisFromRight)
						{
							if (info2.thisFromLeft || info2.thisFromRight)
							{
								return key;
							}
						}
						
						if (info.thisFromTop || info.thisFromBottom)
						{
							if (info2.thisFromTop || info2.thisFromBottom)
							{
								return key;
							}
						}
					}
					else
					{
						return key;
					}
				}
				else
				{
					return key;
				}
			}
		}
		
		return -1;
	}
	
	public function resetReal(x:Float, y:Float)
	{
		realX = x; realY = y;
		colX = realX - Math.floor(cacheWidth/2) - currOffset.x;
		colY = realY - Math.floor(cacheHeight / 2) - currOffset.y;
	}
	
	private function adjustByWidth(posDir:Bool):Float
	{
		if (_mask != null && _mask.lastCheckedMask != null)
		{
			if (isOfType(_mask.lastCheckedMask, Hitbox))
			{
				var box:Hitbox = cast _mask.lastCheckedMask;
				
				if (posDir)
				{
					return (cacheWidth / 2) - (cacheWidth - (box._x + box._width));
				}
				
				return (cacheWidth / 2) - box._x;
			}
		}
		
		return cacheWidth / 2;
	}
	
	private function adjustByHeight(posDir:Bool):Float
	{
		if (_mask != null && _mask.lastCheckedMask != null)
		{
			if (isOfType(_mask.lastCheckedMask, Hitbox))
			{
				var box:Hitbox = cast _mask.lastCheckedMask;
				
				if (posDir)
				{
					return (cacheHeight / 2) - (cacheHeight - (box._y + box._height));
				}
				
				return (cacheHeight / 2) - box._y;
			}
		}
		
		return cacheHeight/ 2;
	}
	
	private function getAllCollisionInfo(xDir:Float, yDir:Float):Collision
	{		
		var solidCollision:Collision = null;
		
		while (listChecked < collidedList.length)
		{
			var lastCollisionInfo:Collision = Collision.get();
			
			colMask = collidedList[listChecked]._mask;			
			
			fillCollisionInfo(lastCollisionInfo, collidedList[listChecked], xDir, yDir);
			addCollision(lastCollisionInfo);
							
			if (lastCollisionInfo.linkedCollision == null)
			{
				var linked:Collision = Collision.get();
								
				lastCollisionInfo.switchData(linked);
				collidedList[listChecked].addCollision(linked);
			}
			
			if (lastCollisionInfo.solidCollision)
			{
				solidCollision = lastCollisionInfo;
			}
			
			listChecked++;
		}	
		
		return solidCollision;			
	}

	public function moveActorBy(x:Float, y:Float, noCollision = true, sweep:Bool = false)
	{
		if (x == 0 && y == 0)
		{
			return;
		}		
		
		clearCollisionInfoList();		
		
		if (!noCollision && collidable && HITBOX.collideTypes != null)
		{
			var solidType = HITBOX.collideTypes;
		
			var sign:Float, signIncr:Float, next:Float, e:Actor;			
			
			if (x != 0)
			{
				next = x > 0 ? Math.ceil(realX + x) : Math.floor(realX + x);
				
				clearCollidedList();
				
				if (sweep || collideTypes(solidType, next, realY) != null)
				{
					clearCollidedList();
					
					while (x != 0)
					{
						signIncr = (x >= 1 || x <= -1) ? 1 : Math.abs(x);
						sign = x > 0 ? signIncr : -signIncr;						
						next = sign > 0 ? Math.ceil(realX + sign) : Math.floor(realX + sign);
						
						//Check regions first
						if ((e = collide(GameModel.REGION_ID, next, realY)) != null)
						{
							cast(e, Region).addActor(this);
						}
						
						if ((e = collideTypes(solidType, next, realY)) != null)
						{							
							var solidCollision:Collision = getAllCollisionInfo(sign, 0);
							
							if (solidCollision != null)
							{
								xSpeed = 0;
								
								if (solidCollision.useBounds)
								{
									if (sign > 0)
									{
										realX = solidCollision.bounds.x - Math.ceil(adjustByWidth(true));
									}
									
									else
									{
										realX = solidCollision.bounds.x + solidCollision.bounds.width + Math.floor(adjustByWidth(false));
									}
								}
								
								break;
							}							
						}
						
						realX += sign;
						x -= sign;						
					}
				}
				else realX += x;
			}						
			if (y != 0)
			{
				next = y > 0 ? Math.ceil(realY + y) : Math.floor(realY + y);
				
				clearCollidedList();
				
				if (sweep || collideTypes(solidType, realX, next) != null)
				{
					clearCollidedList();
					while (y != 0)
					{
						signIncr = (y >= 1 || y <= -1) ? 1 : Math.abs(y);
						sign = y > 0 ? signIncr : -signIncr;
						next = sign > 0 ? Math.ceil(realY + sign) : Math.floor(realY + sign);
						
						//Check regions first
						if ((e = collide(GameModel.REGION_ID, realX, next)) != null)
						{
							cast(e, Region).addActor(this);
						}
						
						if ((e = collideTypes(solidType, realX, next)) != null)
						{		
							var solidCollision:Collision = getAllCollisionInfo(0, sign);
							
							if (solidCollision != null)
							{
								ySpeed = 0;
								
								
								if (solidCollision.useBounds)
								{
									if (sign > 0)
									{
										realY = solidCollision.bounds.y - Math.ceil(adjustByHeight(true));
									}
									
									else
									{
										realY = solidCollision.bounds.y + solidCollision.bounds.height + Math.floor(adjustByHeight(false));
									}
								}
								
								break;
							}
						}
						
						realY += sign;
						y -= sign;
						
					}
				}
				else realY += y;
			}
		}
		else
		{
			realX += x;
			realY += y;
		}
		
		resetReal(realX, realY);
	}	
	
	/**
	 * Moves the Entity to the position, retaining integer values for its x and y.
	 * @param	x			X position.
	 * @param	y			Y position.
	 * @param	solidType	An optional collision type to stop flush against upon collision.
	 * @param	sweep		If sweeping should be used (prevents fast-moving objects from going through solidType).
	 */
	public inline function moveActorTo(x:Float, y:Float, noCollision = true, sweep:Bool = false)
	{
		moveActorBy(x - realX, y - realY, noCollision, sweep);
	}

	/**
	 * Moves towards the target position, retaining integer values for its x and y.
	 * @param	x			X target.
	 * @param	y			Y target.
	 * @param	amount		Amount to move.
	 * @param	solidType	An optional collision type to stop flush against upon collision.
	 * @param	sweep		If sweeping should be used (prevents fast-moving objects from going through solidType).
	 */
	public inline function moveActorTowards(x:Float, y:Float, amount:Float, noCollision = true, sweep:Bool = false)
	{
		_point.x = x - realX;
		_point.y = y - realY;
		_point.normalize(amount);
		moveActorBy(_point.x, _point.y, noCollision, sweep);
	}

	/**
	 * When you collide with an Entity on the x-axis with moveTo() or moveBy().
	 * @param	e		The Entity you collided with.
	 */
	public function moveCollideX(info:Collision, sign:Float)
	{		
	}

	/**
	 * When you collide with an Entity on the y-axis with moveTo() or moveBy().
	 * @param	e		The Entity you collided with.
	 */
	public function moveCollideY(info:Collision, sign:Float)
	{
	}
	
	private function fillCollisionInfo(info:Collision, a:Actor, xDir:Float, yDir:Float)
	{
		if(isOfType(a, Region))
		{
			var region:Region = cast a;
			region.addActor(this);
			return;
		}
	
		info.thisActor = info.actorA = this;
		info.otherActor = info.actorB = a;
		
		info.maskA = _mask;
		info.maskB = colMask;
		info.solidCollision = _mask.solid && colMask.solid;
		
		info.groupA = _mask.lastCheckedMask.groupID;
		info.groupB = _mask.lastCheckedMask.lastColID;	
		 
		var responseMap:Map<Int, String> = Collision.collisionResponses.get(getGroupID());
		var overrideSensor:Bool = false;
		var overridePhysical:Bool = false;
		
		if (responseMap != null && responseMap.get(a.getGroupID()) != null)
		{
			if (responseMap.get(a.getGroupID()) == "sensor")
			{
				info.solidCollision = false;
				overrideSensor = true;
			}
			
			else 
			{
				info.solidCollision = true;
				overridePhysical = true;
			}
		}
		
		if (colMask != null)
		{			
			info.useBounds = true;
			info.bounds.x = colMask.lastBounds.x;
			info.bounds.y = colMask.lastBounds.y;
			info.bounds.width = colMask.lastBounds.width;
			info.bounds.height = colMask.lastBounds.height;
		}
					
		if(xDir != 0)
		{
			//If tile, have to use travel direction
			if (a.ID == Utils.INTEGER_MAX)
			{
				info.thisFromLeft = xDir < 0;
				info.thisFromRight = xDir > 0;
			}
			else
			{			
				info.thisFromLeft = a.colX < colX;
				info.thisFromRight = a.colX > colX;
			}
			
			info.otherFromLeft = !info.thisFromLeft;
			info.otherFromRight = !info.thisFromRight;
		
			info.thisFromTop = info.otherFromTop = false;
			info.thisFromBottom = info.otherFromBottom = false;
		}
		
		if(yDir != 0)
		{
			//If tile, have to use travel direction
			if (a.ID == Utils.INTEGER_MAX)
			{
				info.thisFromTop = yDir < 0;
				info.thisFromBottom = yDir > 0;
			}
			else
			{			
				info.thisFromTop = a.colY < colY;
				info.thisFromBottom = a.colY > colY;
			}
		
			info.otherFromTop = !info.thisFromTop;
			info.otherFromBottom = !info.thisFromBottom;
		
			info.thisFromLeft = info.otherFromLeft = false;
			info.thisFromRight = info.otherFromRight = false;
		}
		
		//TODO
		info.thisCollidedWithActor = true;
		info.thisCollidedWithTile = a.ID == Utils.INTEGER_MAX;
		
		if(info != null)
		{
			info.thisCollidedWithSensor = overrideSensor || !overridePhysical && !info.maskB.solid;
		}
		
		else
		{
			info.thisCollidedWithSensor = false;
		}
		
		info.thisCollidedWithTerrain = false;
		
		info.otherCollidedWithActor = true;
		info.otherCollidedWithTile = a.ID == Utils.INTEGER_MAX;
		
		if(info != null)
		{
			info.otherCollidedWithSensor = !info.maskA.solid;
		}
		
		else
		{
			info.otherCollidedWithSensor = false;
		}
		
		info.otherCollidedWithTerrain = false;
	}
	
	public function handleCollisionsSimple()
	{
		if (collisionsCount > 0)
		{
			for (info in simpleCollisions)
			{
				if (info == null || info.remove == true) continue;
				
				lastCollided = info.otherActor;
				whenCollided.dispatch(info);
				engine.handleCollision(this, info);								
			}
		}
	}
	
	private var HITBOX:Mask;
	private var _mask:Mask;
	private var colMask:Mask;
	private var _x:Float;
	private var _y:Float;
	private var _moveX:Float;
	private var _moveY:Float;
	private var _point:Point;
	private var simpleCollisions:IntHashTable<Collision>;
	private var collidedList:Array<Actor>;
	private var listChecked:Int;
}