package com.stencyl.models.collision;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.geom.Point;
import openfl.geom.Rectangle;

import com.stencyl.models.actor.Collision;
import com.stencyl.models.GameModel;

import com.stencyl.utils.Log;
import com.stencyl.utils.Utils;

/**
 * Uses a hash grid to determine collision, faster than
 * using hundreds of Entities for tiled levels, etc.
 */
class Grid extends Hitbox
{
	/**
	 * If x/y positions should be used instead of columns/rows.
	 */
	public var usePositions:Bool;
	


	/**
	 * Constructor.
	 * @param	width			Width of the grid, in pixels.
	 * @param	height			Height of the grid, in pixels.
	 * @param	tileWidth		Width of a grid tile, in pixels.
	 * @param	tileHeight		Height of a grid tile, in pixels.
	 * @param	x				X offset of the grid.
	 * @param	y				Y offset of the grid.
	 */
	public function new(width:Int, height:Int, tileWidth:Int, tileHeight:Int, x:Int = 0, y:Int = 0)
	{
		super();

		// check for illegal grid size
		if (width == 0 || height == 0 || tileWidth == 0 || tileHeight == 0)
		{
			throw "Illegal Grid, sizes cannot be 0.";
		}				

		_rect = Utils.rect;
		_point = Utils.point;
		_point2 = Utils.point2;

		// set grid properties
		columns = Std.int(width / tileWidth);
		rows = Std.int(height / tileHeight);

		_tile = new Rectangle(0, 0, tileWidth, tileHeight);
		_x = x;
		_y = y;
		_width = width;
		_height = height;
		usePositions = false;
		groupID = GameModel.TERRAIN_ID;

		// set callback functions
		_check.set(Type.getClassName(Mask), collideMask);
		_check.set(Type.getClassName(Hitbox), collideHitbox);
		_check.set(Type.getClassName(Pixelmask), collidePixelmask);

		data = new Array<Array<Bool>>();
		for (x in 0...rows)
		{
			data.push(new Array<Bool>());
		}
	}

	/**
	 * Sets the value of the tile.
	 * @param	column		Tile column.
	 * @param	row			Tile row.
	 * @param	solid		If the tile should be solid.
	 */
	public function setTile(column:Int = 0, row:Int = 0, solid:Bool = true)
	{
		if ( ! checkTile(column, row) ) return;

		if (usePositions)
		{
			column = Std.int(column / _tile.width);
			row = Std.int(row / _tile.height);
		}
		data[row][column] = solid;
	}

	/**
	 * Makes the tile non-solid.
	 * @param	column		Tile column.
	 * @param	row			Tile row.
	 */
	public inline function clearTile(column:Int = 0, row:Int = 0)
	{
		setTile(column, row, false);
	}

	private inline function checkTile(column:Int, row:Int):Bool
	{
		// check that tile is valid
		if (column < 0 || column > columns - 1 || row < 0 || row > rows - 1)
		{
			//Log.error('Tile out of bounds: ' + column + ', ' + row);
			return false;
		}
		else
		{
			return true;
		}
	}

	/**
	 * Gets the value of a tile.
	 * @param	column		Tile column.
	 * @param	row			Tile row.
	 * @return	tile value.
	 */
	public function getTile(column:Int = 0, row:Int = 0):Bool
	{
		if ( ! checkTile(column, row) ) return false;

		if (usePositions)
		{
			column = Std.int(column / _tile.width);
			row = Std.int(row / _tile.height);
		}
		return data[row][column];
	}

	/**
	 * Sets the value of a rectangle region of tiles.
	 * @param	column		First column.
	 * @param	row			First row.
	 * @param	width		Columns to fill.
	 * @param	height		Rows to fill.
	 * @param	fill		Value to fill.
	 */
	public function setRect(column:Int = 0, row:Int = 0, width:Int = 1, height:Int = 1, solid:Bool = true)
	{
		if (usePositions)
		{
			column = Std.int(column / _tile.width);
			row    = Std.int(row / _tile.height);
			width  = Std.int(width / _tile.width);
			height = Std.int(height / _tile.height);
		}

		for (yy in row...(row + height))
		{
			for (xx in column...(column + width))
			{
				setTile(xx, yy, solid);
			}
		}
	}

	/**
	 * Makes the rectangular region of tiles non-solid.
	 * @param	column		First column.
	 * @param	row			First row.
	 * @param	width		Columns to fill.
	 * @param	height		Rows to fill.
	 */
	public inline function clearRect(column:Int = 0, row:Int = 0, width:Int = 1, height:Int = 1)
	{
		setRect(column, row, width, height, false);
	}

	/**
	 * The tile width.
	 */
	public var tileWidth(get, never):Int;
	private inline function get_tileWidth():Int { return Std.int(_tile.width); }

	/**
	 * The tile height.
	 */
	public var tileHeight(get, never):Int;
	private inline function get_tileHeight():Int { return Std.int(_tile.height); }

	/**
	 * How many columns the grid has
	 */
	public var columns(default, null):Int;

	/**
	 * How many rows the grid has.
	 */
	public var rows(default, null):Int;

	/**
	 * The grid data.
	 */
	public var data(default, null):Array<Array<Bool>>;

	/** @private Collides against an Entity. */
	override private function collideMask(other:Mask):Bool
	{		
		var rectX:Int, rectY:Int, pointX:Int, pointY:Int;
		_rect.x = other.parent.colX - parent.colX;
		_rect.y = other.parent.colY - parent.colY;
		pointX  = Std.int((_rect.x + other.parent.cacheWidth - 1) / _tile.width) + 1;
		pointY  = Std.int((_rect.y + other.parent.cacheHeight -1) / _tile.height) + 1;
		rectX   = Std.int(_rect.x / _tile.width);
		rectY   = Std.int(_rect.y / _tile.height);

		for (dy in rectY...pointY)
		{
			for (dx in rectX...pointX)
			{
				if (getTile(dx, dy))
				{
					return true;
				}
			}
		}
		return false;
	}

	/** @private Collides against a Hitbox. */
	override private function collideHitbox(other:Hitbox):Bool
	{
		var rectX:Int, rectY:Int, pointX:Int, pointY:Int;
		_rect.x = other.parent.colX + other._x;
		_rect.y = other.parent.colY + other._y;
		pointX = Std.int((_rect.x + other._width  - 1) / _tile.width) + 1;
		pointY = Std.int((_rect.y + other._height - 1) / _tile.height) + 1;
		rectX  = Std.int(_rect.x / _tile.width);
		rectY  = Std.int(_rect.y / _tile.height);

		for (dy in rectY...pointY)
		{
			for (dx in rectX...pointX)
			{
				if (getTile(dx, dy))
				{					
					lastBounds.x = dx * _tile.width;
					lastBounds.y = dy * _tile.height;
					lastBounds.width = _tile.width;
					lastBounds.height = _tile.height;
			
					other.lastColID = groupID;
					
					return true;
				}
			}
		}
		return false;
	}

	/** @private Collides against a Pixelmask. */
	private function collidePixelmask(other:Pixelmask):Bool
	{
#if flash
		var x1:Int = Std.int(other.parent.colX + other.x - parent.colX - _x),
			y1:Int = Std.int(other.parent.colY + other.y - parent.colY - _y),
			x2:Int = Std.int((x1 + other.width - 1) / _tile.width),
			y2:Int = Std.int((y1 + other.height - 1) / _tile.height);
		_point.x = x1;
		_point.y = y1;
		x1 = Std.int(x1 / _tile.width);
		y1 = Std.int(y1 / _tile.height);
		_tile.x = x1 * _tile.width;
		_tile.y = y1 * _tile.height;
		var xx:Int = x1;
		while (y1 <= y2)
		{
			if (y1 < 0 || y1 >= data.length)
			{
				y1 ++;
				continue;
			}

			while (x1 <= x2)
			{
				if (x1 < 0 || x1 >= data[0].length)
				{
					x1 ++;
					continue;
				}

				if (data[y1][x1])
				{
					if (other.data.hitTest(_point, 1, _tile)) return true;
				}
				x1 ++;
				_tile.x += _tile.width;
			}
			x1 = xx;
			y1 ++;
			_tile.x = x1 * _tile.width;
			_tile.y += _tile.height;
		}
#else
		Log.warn('Pixelmasks will not work in targets other than flash due to hittest not being implemented in openfl.');
#end
		return false;
	}

	/*override public function debugDraw(graphics:Graphics, scaleX:Float, scaleY:Float):Void
	{
		HXP.point.x = _x + parent.x - HXP.camera.x;
		HXP.point.y = _y + parent.y - HXP.camera.y;
		var color = HXP.convertColor(0xFF0000FF);

		HXP.buffer.lock();
		for (i in 1...columns)
		{
			HXP.rect.x = HXP.point.x + i * tileWidth;
			HXP.rect.y = HXP.point.y;
			HXP.rect.width = 1;
			HXP.rect.height = _height;
			HXP.buffer.fillRect(HXP.rect, color);
		}

		for (i in 1...rows)
		{
			HXP.rect.x = HXP.point.x;
			HXP.rect.y = HXP.point.y + i * tileHeight;
			HXP.rect.width = _width;
			HXP.rect.height = 1;
			HXP.buffer.fillRect(HXP.rect, color);
		}

		HXP.rect.width = tileWidth;
		HXP.rect.height = tileHeight;
		for (y in 0...rows)
		{
			HXP.rect.y = HXP.point.y + y * tileHeight;
			for (x in 0...columns)
			{
				HXP.rect.x = HXP.point.x + x * tileWidth;
				if (data[y][x])
				{
					HXP.buffer.fillRect(HXP.rect, color);
				}
			}
		}
		HXP.buffer.unlock();
	}*/

	public function squareProjection(axis:Point, point:Point):Void
	{
		if (axis.x < axis.y)
		{
			point.x = axis.x;
			point.y = axis.y;
		}
		else
		{
			point.y = axis.x;
			point.x = axis.y;
		}
	}

	// Grid information.
	private var _tile:Rectangle;
	private var _rect:Rectangle;
	private var _point:Point;
	private var _point2:Point;
}