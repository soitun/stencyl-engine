package com.stencyl.models.scene;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.PixelSnapping;
import openfl.display.Sprite;
import openfl.display.Tile as FLTile;
import openfl.display.Tilemap;
import openfl.display.Tileset as FLTileset;
import openfl.geom.ColorTransform;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;

import com.stencyl.Config;
import com.stencyl.behavior.BehaviorInstance;
import com.stencyl.graphics.EngineScaleUpdateListener;
import com.stencyl.models.Scene;
import com.stencyl.models.collision.Grid;
import com.stencyl.utils.Log;
import com.stencyl.utils.Utils;

class TileLayer extends Sprite implements EngineScaleUpdateListener
{
	public var layerID:Int;
		
	//Data
	public var rows:Array<Array<Tile>>;
	public var autotileData:Array<Array<Int>>;
	public var grid:Grid;
	
	public var scene:Scene;
	public var numRows:Int;
	public var numCols:Int;

	//Internal/Temporary stuff
	#if !use_tilemap
	public var bitmapData:BitmapData;
	private var flashPoint:Point;
	#else
	private var tilemaps:Map<FLTileset, Tilemap>;
	#end
	private var noTiles:Bool;
	
	#if !use_tilemap
	private static inline var TILESET_CACHE_MULTIPLIER = 1000000;
	private static var cacheSource = new Map<Int,Rectangle>();
	#end

	public static function resetStatics():Void
	{
		#if !use_tilemap
		cacheSource = new Map<Int,Rectangle>();
		#end
	}

	public function new(layerID:Int, scene:Scene, numCols:Int, numRows:Int)
	{
		super();
		
		this.layerID = layerID;
		
		this.scene = scene;
		this.numRows = numRows;
		this.numCols = numCols;
		clear();
		
		#if !use_tilemap
		flashPoint = new Point();
		#else
		tilemaps = new Map<FLTileset, Tilemap>();
		#end
	}
	
	#if !use_tilemap
	public function initBitmap()
	{
		if(!noTiles)
		{
			bitmapData = new BitmapData
			(
				Std.int((Engine.screenWidth * Engine.SCALE) + (scene.tileWidth * Engine.SCALE)), 
				Std.int((Engine.screenHeight * Engine.SCALE) + (scene.tileHeight * Engine.SCALE)), 
				true, 
				0
			);
			
			var bmp = new Bitmap(bitmapData);
			bmp.smoothing = Config.antialias;
			addChild(bmp);
		}
	}
	
	public function clearBitmap()
	{
		while(numChildren > 0)
		{
			removeChildAt(0);
		}
		
		if(bitmapData != null)
		{
			bitmapData.dispose();
		}
		
		bitmapData = null;
	}
	#end
	
	public function clear()
	{
		#if !use_tilemap
		
		if(bitmapData != null)
			clearBitmap();
		
		#else
		
		if(tilemaps != null)
			for(tm in tilemaps)
				tm.removeTiles();
		
		#end
		
		this.noTiles = true;

		rows = [];
		autotileData = [];

		for(row in 0...numRows)
		{
			rows[row] = [];
			autotileData[row] = [];

			for(col in 0...numCols)
			{
				rows[row][col] = null;
				autotileData[row][col] = 0;
			}
		}
	}
	
	public function setPosition(x:Float, y:Float)
	{
		#if !use_tilemap
		this.x = x - x % (scene.tileWidth * Engine.SCALE);
		this.y = y - y % (scene.tileHeight * Engine.SCALE);
		#else
		//this.x = x;
		//this.y = y;
		#end
	}
	
	//TODO: It makes more sense to mount it to this, than make a new actor for it
	public function mountGrid()
	{
		if(grid == null)
		{
			return;
		}
	
		var a = new Actor
		(
			Engine.engine, 
			Utils.INTEGER_MAX,
			GameModel.TERRAIN_ID,
			0, 
			0, 
			-1,
			grid.width, 
			grid.height, 
			null, 
			new Map<String,BehaviorInstance>(),
			null,
			null, 
			false, 
			true, 
			false,
			false, 
			grid,
			Engine.NO_PHYSICS
		);
		
		a.name = "Terrain";
		a.typeID = -1;
		a.visible = false;
		a.ignoreGravity = true;
		
		Engine.engine.getGroup(GameModel.TERRAIN_ID).addChild(a);
	}
	
	public function setTileAt(row:Int, col:Int, tile:Tile, ?updateAutotile:Bool = true)
	{
		if(col < 0 || row < 0 || col >= numCols || row >= numRows)
		{
			return;
		}
		
		if(noTiles && tile != null)
		{
			noTiles = false;

			#if !use_tilemap
			if(bitmapData == null)
				initBitmap();
			#end
		}

		var old:Tile = rows[row][col];
		if(updateAutotile)
		{
			updateAutotile =
	        	(old != null && old.autotiles != null) ||
	        	(tile != null && tile.autotiles != null);
        }

        rows[row][col] = tile;
		autotileData[row][col] = 0;

		if(updateAutotile)
        {
        	updateAutotilesNear(row, col);
        }
	}
	
	public function getTileAt(row:Int, col:Int):Tile
	{
		if(col < 0 || row < 0 || col >= numCols || row >= numRows)
		{
			return null;
		}
		
		return rows[row][col];
	}

	public function updateAutotilesNear(yc:Int, xc:Int):Void
	{
		//Log.verbose('update near $xc, $yc');
		for(y in yc - 1...yc + 2)
		{
			for (x in xc - 1...xc + 2)
			{
				if(x < 0 || y < 0 || x >= numCols || y >= numRows)
					continue;

				updateAutotile(y, x);
			}
		}
	}

	private static var autotileFlagPointMap:Map<Int, Point> = 
	[
		Autotile.CORNER_TL => new Point(-1, -1),
		Autotile.CORNER_TR => new Point(1, -1),
		Autotile.CORNER_BL => new Point(-1, 1),
		Autotile.CORNER_BR => new Point(1, 1),
		Autotile.SIDE_T => new Point(0, -1),
		Autotile.SIDE_B => new Point(0, 1),
		Autotile.SIDE_L => new Point(-1, 0),
		Autotile.SIDE_R => new Point(1, 0)
	];

	public function updateAutotile(y:Int, x:Int):Void
    {
    	var t:Tile = rows[y][x];
    	
		//No need for contextual update if this isn't an autotile, or it's an autotile with an explicitly chosen pattern.
    	if(t == null || t.autotiles == null)
		{
			return;
		}
		
		//Log.verbose('Update autotile: $x, $y');

    	var autotileFlags = 0;
    	
    	for(flag in autotileFlagPointMap.keys())
    	{
    		var point = autotileFlagPointMap.get(flag);
    		var col = Std.int(x + point.x);
    		var row = Std.int(y + point.y);
    		
    		//If the surrounding tile is outside bounds, or equal to this tile, don't add an obstruction flag
    		//TODO: this is where to add a case for autotile merge IDs.
    		if(col < 0 || row < 0 || col >= numCols || row >= numRows || rows[row][col] == t)
    		{
    			continue;
    		}
    		
    		autotileFlags |= flag;
    	}
    	
    	//Log.verbose('Adding flags: $autotileFlags');

    	autotileData[y][x] = t.autotileFormat.animIndex[autotileFlags];
    }
	
	//We're directly drawing since pre-rendering the layer might not be so memory friendly on large levels 
	//and I don't know if it clips.
	public function draw(viewX:Int, viewY:Int)
	{
		if(noTiles)
		{
			return;
		}
		
		#if use_tilemap
		
		for(tm in tilemaps)
			tm.removeTiles();
		
		#else
		
		if(bitmapData == null)
		{
			return;
		}
		bitmapData.fillRect(bitmapData.rect, 0);

		#end
		
		viewX = Math.floor(viewX);
		viewY = Math.floor(viewY);
		
		var width:Int = numCols;
		var height:Int = numRows;
		
		var tw:Int = scene.tileWidth;
		var th:Int = scene.tileHeight;
		
		var fullTw = tw * Engine.SCALE;
		var fullTh = th * Engine.SCALE;
		var halfTw = Std.int(fullTw / 2);
		var halfTh = Std.int(fullTh / 2);
		
		var startX:Int = Std.int(viewX/Engine.SCALE / tw);
		var startY:Int = Std.int(viewY/Engine.SCALE / th);
		var endX:Int = 2 + startX + Std.int(Engine.screenWidth / tw);
		var endY:Int = 2 + startY + Std.int(Engine.screenHeight / th);
		
		endX = Std.int(Math.min(endX, width));
		endY = Std.int(Math.min(endY, height));
		
		var px:Int = 0;
		var py:Int = 0;
		
		var y:Int = startY;	
		
		while(y < endY)
		{
			var x:Int = startX;
			
			while(x < endX)
			{
				var t:Tile = getTileAt(y, x);
				
				if(t == null)
				{
					x++;
					px += tw;
					continue;
				}
				
				#if debug
				if(!t.parent.graphicsLoaded)
				{
					Log.warn("Warning: atlas unloaded for tileset \"" + t.parent.name + "\"");
					x++;
					px += tw;
					continue;
				}
				#end
				
				var baseTileCurrFrame = t.currFrame;

				#if !use_tilemap
				if(cacheSource.get(t.parent.ID * TILESET_CACHE_MULTIPLIER + t.tileID) == null || t.updateSource)
				{
					t.updateSource = false;
					
					if(t.pixels == null && t.autotiles == null)
					{
						cacheSource.set(t.parent.ID * TILESET_CACHE_MULTIPLIER + t.tileID, t.parent.getImageSourceForTile(t.tileID, tw, th));
					}
					
					else
					{
						cacheSource.set(t.parent.ID * TILESET_CACHE_MULTIPLIER + t.tileID, t.getSource(tw, th));
					}						
				}
				
				var source:Rectangle = cacheSource.get(t.parent.ID * TILESET_CACHE_MULTIPLIER + t.tileID);
				
				if(source == null)
				{
					x++;
					px += tw;
					continue;
				}
				
				//If an autotile, swap out the tileset tile for the desired generated tile.
				if(t.autotiles != null)
				{
					t = t.autotiles[autotileData[y][x]];
				}
				
				//If animated or an autotile, used animated tile pixels
				var pixels = (t.pixels == null) ? t.parent.pixels : t.pixels;
				
				flashPoint.x = px * Engine.SCALE;
				flashPoint.y = py * Engine.SCALE;
				
				if(pixels != null)
				{
					bitmapData.copyPixels(pixels, source, flashPoint, null, null, true);
				}
				
				#else

				//If an autotile, swap out the tileset tile for the desired generated tile.
				if(t.autotiles != null)
				{
					t = t.autotiles[autotileData[y][x]];
				}
				if(t.data == null)
				{
					var tileID = t.parent.sheetMap.get(t.tileID);
					getTilemap(t.parent.flTileset).addTile(new FLTile(tileID, x * fullTw, y * fullTh));
				}
				else
				{
					if(t.useSubframes)
					{
						var tm = getTilemap(t.data);
						tm.addTile(new FLTile(t.frameIds[baseTileCurrFrame * 4 + 0], x * fullTw         , y * fullTh         ));
						tm.addTile(new FLTile(t.frameIds[baseTileCurrFrame * 4 + 1], x * fullTw + halfTw, y * fullTh         ));
						tm.addTile(new FLTile(t.frameIds[baseTileCurrFrame * 4 + 2], x * fullTw         , y * fullTh + halfTh));
						tm.addTile(new FLTile(t.frameIds[baseTileCurrFrame * 4 + 3], x * fullTw + halfTw, y * fullTh + halfTh));
					}
					else
					{
						var tileID = t.frameIds[baseTileCurrFrame];
						getTilemap(t.data).addTile(new FLTile(tileID, x * fullTw, y * fullTh));
					}
				}
		  		#end
				
				x++;
				px += tw;
			}
			
			px = 0;
			py += th;
			
			y++;
		}
	}

	public function updateScale():Void
	{
		#if !use_tilemap
		
		clearBitmap();
		initBitmap();
		
		#else
		
		for(tilemap in tilemaps)
		{
			tilemap.width = Engine.sceneWidth * Engine.SCALE;
			tilemap.height = Engine.sceneHeight * Engine.SCALE;
		}
		
		#end
	}
	
	#if !use_tilemap
	public function expandBitmap():Void
	{
		if(!noTiles)
		{
			var desiredWidth = Std.int((Engine.screenWidth * Engine.SCALE) + (scene.tileWidth * Engine.SCALE));
			var desiredHeight = Std.int((Engine.screenHeight * Engine.SCALE) + (scene.tileHeight * Engine.SCALE));
			
			if(bitmapData.width < desiredWidth || bitmapData.height < desiredHeight)
			{
				clearBitmap();
				initBitmap();
			}
		}
	}
	#end

	#if use_tilemap
	private function getTilemap(fltileset:FLTileset):Tilemap
	{
		if(!tilemaps.exists(fltileset))
		{
			var tm = new Tilemap(
				Std.int(Engine.sceneWidth * Engine.SCALE),
				Std.int(Engine.sceneHeight * Engine.SCALE),
				fltileset,
				Config.antialias
			);
			tilemaps.set(fltileset, tm);
			addChild(tm);
		}
		return tilemaps.get(fltileset);
	}
	#end
}