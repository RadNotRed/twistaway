import "./styles.css";

const app = document.querySelector<HTMLDivElement>("#app");

if (!app) {
  throw new Error("Missing app root");
}

app.innerHTML = `
  <header class="topbar">
    <a class="brand" href="#home" aria-label="MotoPlanner home">
      <span class="brand-mark"></span>
      <span>MotoPlanner</span>
    </a>
    <nav aria-label="Primary navigation">
      <a href="#features">Features</a>
      <a href="#security">Security</a>
      <a href="#legal">Legal</a>
    </nav>
  </header>

  <main id="home">
    <section class="hero">
      <div class="hero-copy">
        <p class="eyebrow">Android, iPhone, offline-ready</p>
        <h1>MotoPlanner</h1>
        <p>
          A motorcycle route planner for riders who care about curves, scenery,
          weather windows, traffic reality, and keeping their ride history private.
        </p>
        <div class="hero-actions">
          <a class="button primary" href="#features">Explore</a>
          <a class="button secondary" href="#security">Security</a>
        </div>
      </div>
      <div class="phone-preview" aria-label="Route planner preview">
        <div class="map-grid">
          <span class="road road-a"></span>
          <span class="road road-b"></span>
          <span class="route-line"></span>
          <span class="pin start"></span>
          <span class="pin end"></span>
        </div>
        <div class="sheet">
          <div>
            <strong>Blue Ridge Morning</strong>
            <span>142 mi · 4h 12m · scenic high</span>
          </div>
          <div class="chips">
            <span>Twisty</span>
            <span>Avoid highways</span>
            <span>Weather aware</span>
          </div>
        </div>
      </div>
    </section>

    <section id="features" class="section">
      <div class="section-heading">
        <p class="eyebrow">Planner</p>
        <h2>Built around how riders actually choose roads.</h2>
      </div>
      <div class="feature-grid">
        <article>
          <h3>Ride Preferences</h3>
          <p>Weight twisties, scenic views, straight roads, highways, tolls, gravel, fuel stops, and rest breaks.</p>
        </article>
        <article>
          <h3>Weather Windows</h3>
          <p>Plan around rain, wind, temperature, visibility, and storm risk using a provider adapter.</p>
        </article>
        <article>
          <h3>Traffic Layers</h3>
          <p>Custom map colors and optional incident feeds, with Waze handoff handled as a partner-gated integration.</p>
        </article>
        <article>
          <h3>Voice Guidance</h3>
          <p>Turn-by-turn prompts are designed for headset use, quick glances, and gloves-on riding.</p>
        </article>
      </div>
    </section>

    <section id="security" class="section split">
      <div>
        <p class="eyebrow">Privacy</p>
        <h2>Routes and logs are encrypted before they settle in storage.</h2>
      </div>
      <ul class="security-list">
        <li>Argon2id password hashing with per-password salts.</li>
        <li>AES-256-GCM payload envelopes for routes, home address, and account-linked logs.</li>
        <li>SQLite backend and SQLCipher-ready mobile storage for offline use.</li>
        <li>Usernames and emails remain searchable account fields by design.</li>
      </ul>
    </section>

    <section id="legal" class="section legal">
      <div class="section-heading">
        <p class="eyebrow">Policies</p>
        <h2>Legal pages are part of the monorepo.</h2>
      </div>
      <div class="legal-links">
        <a href="/privacy.html">Privacy Policy</a>
        <a href="/terms.html">Terms of Service</a>
        <a href="/security.html">Data Security</a>
      </div>
    </section>
  </main>
`;
