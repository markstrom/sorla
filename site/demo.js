// Adds a pause button under the demo on the start page (WCAG 2.2.2). The button stays pressed until it is
// pressed again, whatever the pointer or focus does. Without this script the demo still stops under the
// pointer or with focus, and it stands still for anyone who prefers less motion (then the button is hidden).
const demo = document.querySelector('.demo');
const stage = demo && demo.querySelector('.stage');
if (stage) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'demo-toggle';
  button.setAttribute('aria-pressed', 'false');
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', 'M9 6.5v11M15 6.5v11');
  svg.append(path);
  const label = document.createElement('span');
  label.textContent = 'Pausa';
  const more = document.createElement('span');
  more.className = 'visually-hidden';
  more.textContent = ' animationen';
  button.append(svg, label, more);
  button.addEventListener('click', () => {
    const paused = button.getAttribute('aria-pressed') !== 'true';
    button.setAttribute('aria-pressed', String(paused));
    stage.classList.toggle('is-paused', paused);
  });
  demo.classList.add('has-toggle');
  demo.append(button);
}
