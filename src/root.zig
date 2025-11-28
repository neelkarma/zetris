const std = @import("std");
const Random = std.Random;
const Allocator = std.heap.Allocator;

const BOARD_HEIGHT = 22;
const BOARD_WIDTH = 10;

const Vec2 = struct {
    x: i8,
    y: i8,
    fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ a.x + b.x, a.y + b.y };
    }
};

const Piece = enum {
    I,
    O,
    S,
    Z,
    L,
    J,
    T,

    fn coords(comptime self: Piece) [4]Vec2 {
        return switch (self) {
            .I => .{ .{ -1, 0 }, .{ 0, 0 }, .{ 1, 0 }, .{ 2, 0 } },
            .J => .{ .{ -1, -1 }, .{ -1, 0 }, .{ 0, 0 }, .{ 1, 0 } },
            .L => .{ .{ -1, 0 }, .{ 0, 0 }, .{ 1, 0 }, .{ 1, -1 } },
            .O => .{ .{ 0, 0 }, .{ 0, -1 }, .{ 1, 0 }, .{ 1, -1 } },
            .S => .{ .{ -1, 0 }, .{ 0, 0 }, .{ 0, -1 }, .{ 1, -1 } },
            .Z => .{ .{ -1, -1 }, .{ 0, -1 }, .{ 0, 0 }, .{ 1, 0 } },
            .T => .{ .{ -1, 0 }, .{ 0, 0 }, .{ 0, -1 }, .{ 1, 0 } },
        };
    }
};

fn rotateCoords(coords: [4]Vec2, rotation: u3) void {
    for (coords) |point| {
        var r: u3 = 0;
        while (r < rotation) : (r += 1) {
            const temp = point.x;
            point.x = -point.y;
            point.y = temp;
        }
    }
}

const PieceGenerator = struct {
    ptr: *anyopaque,
    v_next: *const fn (*anyopaque) Piece,
    const Self = @This();

    fn next(self: Self) Piece {
        return self.v_next(self.ptr);
    }
};

const SevenBagGenerator = struct {
    bag: [7]Piece = .{ Piece.I, Piece.O, Piece.S, Piece.Z, Piece.L, Piece.J, Piece.T },
    index: u3 = 0,
    rng: Random,
    generator: PieceGenerator,

    const Self = @This();

    fn init(rng: Random) Self {
        const new: Self = .{
            .rng = rng,
            .generator = .{ .v_next = Self.next },
        };
        new.generator.ptr = &new;
        new.shuffle();
        return new;
    }

    fn shuffle(self: *Self) void {
        self.rng.shuffleWithIndex(Piece, self.bag, u8);
    }

    fn next(self: *Self) Piece {
        const out = self.bag[self.index];
        self.index += 1;
        if (self.index >= 7) {
            self.shuffle();
            self.index = 0;
        }
        return out;
    }
};

const RandomGenerator = struct {
    rng: Random,
    generator: PieceGenerator,

    const Self = @This();

    fn init(rng: Random) Self {
        const new: Self = .{
            .rng = rng,
            .generator = .{ .v_next = Self.next },
        };
        new.generator.ptr = &new;
        return new;
    }

    fn next(self: *Self) Piece {
        return self.rng.enumValue(Piece);
    }
};

const Board = struct {
    cells: [BOARD_HEIGHT][BOARD_WIDTH]?Piece = .{.{null} ** BOARD_WIDTH} ** BOARD_HEIGHT,
    pieceGenerator: PieceGenerator,
    currentPiece: Piece,
    nextPiece: Piece,
    holdPiece: ?Piece = null,
    currentPiecePos: Vec2 = .{ 5, 1 },
    currentRotation: u3 = 0,
    timeSinceLastDrop: u64 = 0,
    justHeld: bool = false,

    const Self = @This();

    fn init(rng: Random) Self {
        const new: Self = .{
            .pieceGenerator = SevenBagGenerator.init(rng).generator,
        };
        new.currentPiece = new.pieceGenerator.next();
        new.nextPiece = new.pieceGenerator.next();
        return new;
    }

    fn tick(self: *Self, dt: u64) bool {
        self.timeSinceLastDrop += dt;
        if (self.timeSinceLastDrop < 1000) return;
        self.timeSinceLastDrop = 0;

        // attempt to drop piece
        if (!self.gravityDrop()) return;

        // if topout, end game
    }

    /// Lowers the current piece by 1 cell. If blocked, returns true and does nothing.
    fn gravityDrop(self: *Self) bool {
        self.currentPiecePos.y += 1;
        var coords = self.currentPiece.coords();
        rotateCoords(&coords, self.currentRotation);
        for (coords) |coord| {
            const boardCoord: Vec2 = coord.add(self.currentPiecePos);
            if (self.cells[boardCoord.y][boardCoord.x] != null or boardCoord.y >= BOARD_HEIGHT) {
                self.currentPiecePos.y -= 1;
                return true;
            }
        }
        return false;
    }

    /// Locks the current piece in position, modifying the cells array.
    fn lockPiece(self: *Self) void {
        var coords = self.currentPiece.coords();
        rotateCoords(&coords, self.currentRotation);
        for (coords) |coord| {
            const boardCoord: Vec2 = coord.add(self.currentPiecePos);
            self.cells[boardCoord.y][boardCoord.x] = self.currentPiece;
        }
    }

    fn softDrop(self: *Self) void {
        self.gravityDrop();
        // TODO: score
    }

    fn hardDrop(self: *Self) void {
        while (!self.gravityDrop()) {}
        self.lockPiece();
        // TODO: score
    }

    fn move(self: *Self, right: bool) void {
        _ = right; // autofix
        _ = self; // autofix
    }

    fn rotate(self: *Self, clockwise: bool) void {
        const newRotation: u3 = undefined;
        if (clockwise) {
            newRotation = if (self.currentRotation == 3) 0 else self.currentRotation + 1;
        } else {
            newRotation = if (self.currentRotation == 0) 3 else self.currentRotation - 1;
        }

        // TODO: check new rotation, incorporate SRS
    }

    fn hold(self: *Self) !void {
        if (self.justHeld) return;
        const toBeHeld = self.currentPiece;
        if (self.holdPiece) |piece| {
            self.currentPiece = piece;
        } else {
            self.currentPiece = self.nextPiece;
            self.nextPiece = self.pieceGenerator.next();
        }
        self.holdPiece = toBeHeld;
        self.currentPiecePos = .{ 5, 1 };

        // TODO: check for game over
    }
};
