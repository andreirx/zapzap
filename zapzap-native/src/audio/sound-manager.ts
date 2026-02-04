// Sound manager using Web Audio API.
// Preloads all sound effects and background music.

// SoundEvent enum values matching Rust components.rs SoundEvent repr(u8)
const SOUND_NAMES: Record<number, string> = {
  0: 'rotate',
  1: 'explode',
  2: 'bomb',
  3: 'coindrop',
  4: 'powerup',
  5: 'bop',
  6: 'buzz',
  7: 'nope',
};

const AUDIO_BASE = '/audio/';

export class SoundManager {
  private ctx: AudioContext | null = null;
  private buffers: Map<string, AudioBuffer> = new Map();
  private musicSource: AudioBufferSourceNode | null = null;
  private musicGain: GainNode | null = null;
  private loaded = false;

  async init(): Promise<void> {
    this.ctx = new AudioContext();

    // Preload all sound effects
    const names = Object.values(SOUND_NAMES);
    const loads = names.map((name) => this.loadSound(name));
    // Also load background music
    loads.push(this.loadSound('IttyBitty'));

    await Promise.all(loads);
    this.loaded = true;
  }

  private async loadSound(name: string): Promise<void> {
    if (!this.ctx) return;
    const ext = name === 'IttyBitty' ? '.mp3' : '.wav';
    try {
      const response = await fetch(`${AUDIO_BASE}${name}${ext}`);
      const arrayBuffer = await response.arrayBuffer();
      const audioBuffer = await this.ctx.decodeAudioData(arrayBuffer);
      this.buffers.set(name, audioBuffer);
    } catch {
      console.warn(`Failed to load sound: ${name}`);
    }
  }

  /// Resume AudioContext (required after user gesture).
  async resume(): Promise<void> {
    if (this.ctx?.state === 'suspended') {
      await this.ctx.resume();
    }
  }

  /// Play a sound event by its numeric ID (matching Rust SoundEvent enum).
  play(eventId: number): void {
    const name = SOUND_NAMES[eventId];
    if (!name) return;
    this.playByName(name);
  }

  /// Play a sound by name.
  playByName(name: string): void {
    if (!this.ctx || !this.loaded) return;
    const buffer = this.buffers.get(name);
    if (!buffer) return;

    const source = this.ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(this.ctx.destination);
    source.start();
  }

  /// Start background music (looped).
  startMusic(): void {
    if (!this.ctx || !this.loaded) return;
    this.stopMusic();

    const buffer = this.buffers.get('IttyBitty');
    if (!buffer) return;

    this.musicGain = this.ctx.createGain();
    this.musicGain.gain.value = 0.3;
    this.musicGain.connect(this.ctx.destination);

    this.musicSource = this.ctx.createBufferSource();
    this.musicSource.buffer = buffer;
    this.musicSource.loop = true;
    this.musicSource.connect(this.musicGain);
    this.musicSource.start();
  }

  /// Stop background music.
  stopMusic(): void {
    if (this.musicSource) {
      try {
        this.musicSource.stop();
      } catch {
        // Already stopped
      }
      this.musicSource = null;
    }
    this.musicGain = null;
  }
}
