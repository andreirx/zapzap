import { useCallback, useEffect, useRef, useState, type CSSProperties } from 'react';
import './App.css';
import { initRenderer, type Renderer } from './renderer';
import { SoundManager } from './audio/sound-manager';

// Game constants matching Rust state.rs
const TILE_SIZE = 50;
const GRID_OFFSET_X = 225;
const GRID_OFFSET_Y = 25;
const INSTANCE_FLOATS = 8;
const EFFECTS_VERTEX_FLOATS = 5;
const HEADER_FLOATS = 10;
const MAX_INSTANCES = 256;
const INSTANCE_DATA_FLOATS = MAX_INSTANCES * INSTANCE_FLOATS;

// Game phases matching Rust GamePhase enum
const PHASE_GAME_OVER = 5;

// Game modes matching Rust GameMode enum
const MODE_ZEN = 0;
const MODE_VS_BOT = 1;

type GameScreen = 'menu' | 'playing' | 'paused' | 'gameover';

function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const workerRef = useRef<Worker | null>(null);
  const rendererRef = useRef<Renderer | null>(null);
  const sharedF32Ref = useRef<Float32Array | null>(null);
  const rafRef = useRef<number>(0);
  const soundRef = useRef<SoundManager | null>(null);

  const [screen, setScreen] = useState<GameScreen>('menu');
  const [leftScore, setLeftScore] = useState(0);
  const [rightScore, setRightScore] = useState(0);
  const [boardWidth, setBoardWidth] = useState(12);
  const [boardHeight, setBoardHeight] = useState(10);
  const [gameMode, setGameMode] = useState(MODE_ZEN);
  const [powerState, setPowerState] = useState(0);
  const [popups, setPopups] = useState<Array<{ id: number; x: number; y: number; value: number; side: number }>>([]);
  const popupIdRef = useRef(0);
  const [rendererBackend, setRendererBackend] = useState<'webgpu' | 'canvas2d' | null>(null);
  const [rendererKey, setRendererKey] = useState(0);
  const [force2D, setForce2D] = useState(false);

  // Render loop: read SharedArrayBuffer and draw
  const renderLoop = useCallback(() => {
    const renderer = rendererRef.current;
    const sharedF32 = sharedF32Ref.current;
    if (!renderer || !sharedF32) {
      rafRef.current = requestAnimationFrame(renderLoop);
      return;
    }

    // Read header
    const phase = sharedF32[2];
    const lScore = sharedF32[3];
    const rScore = sharedF32[4];
    const instanceCount = sharedF32[5];
    const bw = sharedF32[6];
    const bh = sharedF32[7];
    const effectsVertCount = sharedF32[8];
    const pState = sharedF32[9];

    setLeftScore(Math.floor(lScore));
    setRightScore(Math.floor(rScore));
    if (bw > 0) setBoardWidth(Math.floor(bw));
    if (bh > 0) setBoardHeight(Math.floor(bh));
    setPowerState(Math.floor(pState));

    if (phase === PHASE_GAME_OVER && screen === 'playing') {
      setScreen('gameover');
      soundRef.current?.stopMusic();
    }

    // Draw instances + effects
    if (instanceCount > 0) {
      const instanceData = new Float32Array(
        sharedF32.buffer,
        HEADER_FLOATS * 4,
        instanceCount * INSTANCE_FLOATS,
      );

      // Tile + pin instances come first; bonuses are appended after.
      // tileCount = left_pins + game_tiles + right_pins = bw*bh + 2*bh
      const tileInstanceCount = Math.min(
        Math.floor(bw) * Math.floor(bh) + 2 * Math.floor(bh),
        instanceCount,
      );

      let effectsData: Float32Array | undefined;
      let effectsVertexCount: number | undefined;
      if (effectsVertCount > 0) {
        const effectsOffset = (HEADER_FLOATS + INSTANCE_DATA_FLOATS) * 4;
        effectsData = new Float32Array(
          sharedF32.buffer,
          effectsOffset,
          effectsVertCount * EFFECTS_VERTEX_FLOATS,
        );
        effectsVertexCount = effectsVertCount;
      }

      renderer.draw(instanceData, instanceCount, tileInstanceCount, effectsData, effectsVertexCount);
    }

    rafRef.current = requestAnimationFrame(renderLoop);
  }, [screen]);

  // Initialize renderer and worker
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    // Set canvas size to device pixels
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.floor(canvas.clientWidth * dpr);
    canvas.height = Math.floor(canvas.clientHeight * dpr);

    let cleanup = false;

    async function setup() {
      try {
        const renderer = await initRenderer(canvas!, force2D);
        if (cleanup) return;
        rendererRef.current = renderer;
        setRendererBackend(renderer.backend);

        // Start render loop
        rafRef.current = requestAnimationFrame(renderLoop);
      } catch {
        if (cleanup) return;
        // WebGPU failed after locking the canvas — force React to recreate
        // the <canvas> element, then retry with Canvas 2D.
        if (!force2D) {
          console.warn('[App] WebGPU locked canvas, remounting for Canvas 2D fallback');
          setForce2D(true);
          setRendererKey(k => k + 1);
        }
      }
    }

    setup();

    // Handle resize
    const onResize = () => {
      if (!canvas || !rendererRef.current) return;
      const dpr = window.devicePixelRatio || 1;
      const w = Math.floor(canvas.clientWidth * dpr);
      const h = Math.floor(canvas.clientHeight * dpr);
      rendererRef.current.resize(w, h);
    };
    window.addEventListener('resize', onResize);

    return () => {
      cleanup = true;
      cancelAnimationFrame(rafRef.current);
      window.removeEventListener('resize', onResize);
    };
  }, [renderLoop, force2D, rendererKey]);

  // Start game with specific mode
  const startGame = useCallback(async (mode: number) => {
    setScreen('playing');
    setLeftScore(0);
    setRightScore(0);
    setGameMode(mode);

    // Init sound on first game start (requires user gesture)
    if (!soundRef.current) {
      const sm = new SoundManager();
      await sm.init();
      soundRef.current = sm;
    }
    await soundRef.current.resume();
    soundRef.current.startMusic();

    // Create worker
    const worker = new Worker(
      new URL('./worker/sim.worker.ts', import.meta.url),
      { type: 'module' },
    );

    worker.onmessage = (e) => {
      if (e.data.type === 'ready' && e.data.sharedBuffer) {
        // SharedArrayBuffer path: set once, main thread reads directly
        sharedF32Ref.current = new Float32Array(e.data.sharedBuffer);
      } else if (e.data.type === 'frame') {
        // postMessage fallback: update ref with each received frame copy
        sharedF32Ref.current = new Float32Array(e.data.buffer);
      } else if (e.data.type === 'sound' && soundRef.current) {
        for (const eventId of e.data.events) {
          soundRef.current.play(eventId);
        }
      } else if (e.data.type === 'popup') {
        const canvas = canvasRef.current;
        if (!canvas) return;
        const rect = canvas.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        const gameWidth = 1050;
        const gameHeight = 550;
        const canvasAspect = (rect.width * dpr) / (rect.height * dpr);
        const gameAspect = gameWidth / gameHeight;
        let projWidth = gameWidth;
        let projHeight = gameHeight;
        if (canvasAspect > gameAspect) {
          projWidth = gameHeight * canvasAspect;
        } else {
          projHeight = gameWidth / canvasAspect;
        }

        const newPopups = e.data.popups.map((p: { x: number; y: number; value: number; side: number }) => {
          const cssX = (p.x / projWidth) * rect.width;
          const cssY = (p.y / projHeight) * rect.height;
          const id = ++popupIdRef.current;
          setTimeout(() => {
            setPopups(prev => prev.filter(pp => pp.id !== id));
          }, 2500);
          return { id, x: cssX, y: cssY, value: p.value, side: p.side };
        });
        setPopups(prev => [...prev, ...newPopups]);
      }
    };

    worker.postMessage({ type: 'init', mode });
    workerRef.current = worker;
  }, []);

  // Handle canvas pointer down -> convert to tile coordinates -> send to worker
  const handlePointerDown = useCallback(
    (e: React.PointerEvent<HTMLCanvasElement>) => {
      if (screen !== 'playing') return;
      const worker = workerRef.current;
      const canvas = canvasRef.current;
      if (!worker || !canvas) return;

      const rect = canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;

      const canvasX = (e.clientX - rect.left) * dpr;
      const canvasY = (e.clientY - rect.top) * dpr;

      const gameWidth = 1050;
      const gameHeight = 550;
      const canvasAspect = canvas.width / canvas.height;
      const gameAspect = gameWidth / gameHeight;

      let projWidth = gameWidth;
      let projHeight = gameHeight;
      if (canvasAspect > gameAspect) {
        projWidth = gameHeight * canvasAspect;
      } else {
        projHeight = gameWidth / canvasAspect;
      }

      const gameX = (canvasX / canvas.width) * projWidth;
      const gameY = (canvasY / canvas.height) * projHeight;

      const tileX = Math.floor((gameX - GRID_OFFSET_X) / TILE_SIZE);
      const tileY = Math.floor((gameY - GRID_OFFSET_Y) / TILE_SIZE);

      if (tileX >= 0 && tileX < boardWidth && tileY >= 0 && tileY < boardHeight) {
        worker.postMessage({ type: 'tap', x: tileX, y: tileY });
      }
    },
    [screen, boardWidth, boardHeight],
  );

  // Pause/Resume
  const togglePause = useCallback(() => {
    if (screen === 'playing') {
      workerRef.current?.postMessage({ type: 'stop' });
      soundRef.current?.stopMusic();
      setScreen('paused');
    } else if (screen === 'paused') {
      workerRef.current?.postMessage({ type: 'resume' });
      soundRef.current?.startMusic();
      setScreen('playing');
    }
  }, [screen]);

  // Quit to menu
  const quitToMenu = useCallback(() => {
    if (workerRef.current) {
      workerRef.current.postMessage({ type: 'stop' });
      workerRef.current.terminate();
      workerRef.current = null;
    }
    sharedF32Ref.current = null;
    soundRef.current?.stopMusic();
    setScreen('menu');
  }, []);

  // Restart game (same mode)
  const restartGame = useCallback(() => {
    if (workerRef.current) {
      workerRef.current.postMessage({ type: 'stop' });
      workerRef.current.terminate();
      workerRef.current = null;
    }
    sharedF32Ref.current = null;
    soundRef.current?.stopMusic();
    startGame(gameMode);
  }, [startGame, gameMode]);

  // Power-up arm/disarm
  const armPower = useCallback((side: 'left' | 'right', ptype: number) => {
    workerRef.current?.postMessage({ type: 'arm_power', side, ptype });
  }, []);

  // Power-up state helpers
  const hasLeftBomb = (powerState & (1 << 0)) !== 0;
  const hasLeftCross = (powerState & (1 << 1)) !== 0;
  const hasLeftArrow = (powerState & (1 << 2)) !== 0;
  const hasRightBomb = (powerState & (1 << 3)) !== 0;
  const hasRightCross = (powerState & (1 << 4)) !== 0;
  const hasRightArrow = (powerState & (1 << 5)) !== 0;
  const armedLeftBomb = (powerState & (1 << 6)) !== 0;
  const armedLeftCross = (powerState & (1 << 7)) !== 0;
  const armedLeftArrow = (powerState & (1 << 8)) !== 0;
  const armedRightBomb = (powerState & (1 << 9)) !== 0;
  const armedRightCross = (powerState & (1 << 10)) !== 0;
  const armedRightArrow = (powerState & (1 << 11)) !== 0;

  // Game over result text
  const gameOverText = () => {
    if (gameMode === MODE_ZEN) {
      return `Score: ${leftScore}`;
    }
    if (leftScore > rightScore) return 'You Win!';
    if (leftScore < rightScore) return 'Bot Wins!';
    return 'Draw!';
  };

  return (
    <div className="game-container">
      <canvas
        key={rendererKey}
        ref={canvasRef}
        className="game-canvas"
        onPointerDown={handlePointerDown}
      />

      {/* Fallback renderer warning */}
      {rendererBackend === 'canvas2d' && (
        <div className="fallback-banner">
          Running in compatibility mode (no HDR). For the best experience, enable WebGPU in Chrome or Safari (via Develop - Feature Flags).
        </div>
      )}

      {/* HUD */}
      {(screen === 'playing' || screen === 'paused') && (
        <div className="hud">
          {gameMode === MODE_ZEN ? (
            <span className="score score-zen">SCORE: {leftScore}</span>
          ) : (
            <>
              <span className="score score-left">YOU: {leftScore}</span>
              <span className="score score-right">BOT: {rightScore}</span>
            </>
          )}
          <button className="pause-btn" onClick={togglePause}>
            {screen === 'paused' ? '>' : 'II'}
          </button>
        </div>
      )}

      {/* Power-up buttons (left side) */}
      {(screen === 'playing') && (hasLeftBomb || hasLeftCross || hasLeftArrow) && (
        <div className="power-buttons power-left">
          {hasLeftBomb && (
            <button
              className={`power-btn ${armedLeftBomb ? 'armed' : ''}`}
              onClick={() => armPower('left', 0)}
              title="Bomb: Clear 5x5 area"
            >B</button>
          )}
          {hasLeftCross && (
            <button
              className={`power-btn ${armedLeftCross ? 'armed' : ''}`}
              onClick={() => armPower('left', 1)}
              title="Cross: Full connections"
            >+</button>
          )}
          {hasLeftArrow && (
            <button
              className={`power-btn ${armedLeftArrow ? 'armed' : ''}`}
              onClick={() => armPower('left', 2)}
              title="Arrow: Clear column"
            >|</button>
          )}
        </div>
      )}

      {/* Power-up buttons (right side) */}
      {(screen === 'playing') && (hasRightBomb || hasRightCross || hasRightArrow) && (
        <div className="power-buttons power-right">
          {hasRightBomb && (
            <button
              className={`power-btn ${armedRightBomb ? 'armed' : ''}`}
              onClick={() => armPower('right', 0)}
              title="Bomb"
            >B</button>
          )}
          {hasRightCross && (
            <button
              className={`power-btn ${armedRightCross ? 'armed' : ''}`}
              onClick={() => armPower('right', 1)}
              title="Cross"
            >+</button>
          )}
          {hasRightArrow && (
            <button
              className={`power-btn ${armedRightArrow ? 'armed' : ''}`}
              onClick={() => armPower('right', 2)}
              title="Arrow"
            >|</button>
          )}
        </div>
      )}

      {/* Start Menu */}
      {screen === 'menu' && (
        <div className="menu-overlay">
          <h1>ZapZap</h1>
          <button onClick={() => startGame(MODE_ZEN)}>Zen Mode</button>
          <button onClick={() => startGame(MODE_VS_BOT)}>Vs Bot</button>
        </div>
      )}

      {/* Pause Overlay */}
      {screen === 'paused' && (
        <div className="pause-overlay">
          <h2>Paused</h2>
          <button onClick={togglePause}>Resume</button>
          <button onClick={quitToMenu}>Quit to Menu</button>
        </div>
      )}

      {/* Game Over */}
      {screen === 'gameover' && (
        <div className="game-over-overlay">
          <h2>{gameOverText()}</h2>
          {gameMode === MODE_VS_BOT && (
            <div className="final-score">
              {leftScore} - {rightScore}
            </div>
          )}
          <button onClick={restartGame}>Play Again</button>
          <button onClick={quitToMenu}>Menu</button>
        </div>
      )}

      {/* Score popups */}
      {popups.map(p => (
        <span
          key={p.id}
          className={`score-popup ${p.side === 0 ? 'left' : 'right'}`}
          style={{ left: p.x, top: p.y } as CSSProperties}
        >
          +{p.value}
        </span>
      ))}
    </div>
  );
}

export default App;
