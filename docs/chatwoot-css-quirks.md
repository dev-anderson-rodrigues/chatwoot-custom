# Chatwoot CSS & Styling Quirks

Quirks descobertos durante o desenvolvimento da página Gestão de Cobrança.
Documentados para evitar retrabalho em futuras implementações.

---

## 1. Input padding-left forçado por CSS de alta especificidade

### Problema
Chatwoot possui uma regra CSS global que força `padding-left: 0.75rem` em todos os inputs:

```css
input[type]:not([type="file"]):not([type="radio"]):not([type="checkbox"]):not(.reset-base):not(.no-margin) {
  padding-left: 0.75rem;
}
```

Esta regra tem **especificidade muito alta** e **sobrepõe classes Tailwind** como `pl-0`, `pl-9`, `pl-10`, etc.

### Sintoma
Um ícone posicionado absolutamente em `left: 8px` ou `left: 12px` fica **em cima do texto** porque o texto começa em `12px` (forçado pelo `padding-left: 0.75rem`), não onde o Tailwind especificou.

**Verificado via DevTools:**
```js
// input com classe pl-9 (esperado: 36px) → computado: 12px
window.getComputedStyle(input).paddingLeft // "12px"
```

### Solução
Adicionar a classe `no-margin` ao input para excluí-lo da regra:

```html
<!-- ERRADO: padding-left será 12px, não 36px -->
<input class="pl-9 ..." />

<!-- CORRETO: padding-left respeitado -->
<input class="no-margin pl-9 ..." />
```

---

## 2. Alinhamento de ícone em campo de busca

### Problema
Posicionamento absoluto do ícone (`absolute top-1/2 -translate-y-1/2 left-3`) **não funciona** confiavelmente no Chatwoot porque:

- O container flex não tem altura constrainada de forma previsível
- A regra de `padding-left` acima faz o texto começar no mesmo ponto que o ícone
- O ícone fica sobreposto ao texto ou desalinhado verticalmente

### Tentativas que falharam
```html
<!-- Não funciona: ícone pode ficar desalinhado ou sobrepor texto -->
<div class="relative">
  <span class="absolute left-3 top-1/2 -translate-y-1/2 i-lucide-search" />
  <input class="pl-9" />
</div>

<!-- Não funciona: mesma causa raiz -->
<div class="relative">
  <span class="absolute inset-y-0 my-auto left-3 i-lucide-search" />
  <input class="pl-9 no-margin" />
</div>
```

### Solução correta: label flex
Usar um `<label>` como container flex com o ícone como filho inline (não posicionado absolutamente):

```html
<label class="flex items-center gap-2 flex-1 h-9 px-3 rounded-lg border border-n-weak bg-n-background focus-within:border-n-brand transition-colors cursor-text">
  <span class="i-lucide-search w-4 h-4 text-n-slate-10 shrink-0" />
  <input
    v-model="search"
    type="text"
    placeholder="Buscar..."
    class="flex-1 min-w-0 no-margin h-full py-0 bg-transparent text-sm text-n-slate-12 placeholder-n-slate-10 focus:outline-none"
  />
</label>
```

**Por que funciona:**
- Ícone e input são irmãos no mesmo flex container → alinhamento controlado por `items-center` e `gap-2`
- `no-margin` no input remove o `padding-left` forçado → input começa logo após o gap
- `shrink-0` no ícone impede que ele encolha
- Altura fixa `h-9` no label define o contexto de alinhamento vertical
- `h-full py-0` no input faz ele preencher a altura sem padding vertical extra

---

## 3. Focus ring vs border-color

### Problema
`focus-within:ring-1 focus-within:ring-n-brand` cria um **glow azul brilhante** muito intrusivo (box-shadow + anel visível), inconsistente com o design system do Chatwoot.

### Solução
Usar apenas mudança de cor de borda no focus:

```html
<!-- EVITAR: ring cria glow proeminente -->
<label class="... focus-within:ring-1 focus-within:ring-n-brand">

<!-- CORRETO: apenas muda a cor da borda -->
<label class="... border border-n-weak focus-within:border-n-brand transition-colors">
```

---

## 4. Tokens de cor do design system

Tokens principais do Chatwoot para referência:

| Token | Valor (dark mode) | Uso |
|-------|-------------------|-----|
| `bg-n-surface-1` | Fundo da página | Wrapper de página |
| `bg-n-solid-2` | Fundo de card | Cards, dropdowns |
| `bg-n-background` | `rgba(0,0,0,0.2)` | Inputs, backgrounds sutis |
| `bg-n-brand` | `rgb(39, 129, 246)` | Botão primário, CTA |
| `border-n-weak` | Borda sutil | Dividers, bordas de cards |
| `outline-n-container` | Outline de card | Cards com `outline outline-1 -outline-offset-1` |
| `text-n-slate-12` | Texto primário | Títulos, conteúdo principal |
| `text-n-slate-11` | Texto secundário | Labels, descrições |
| `text-n-slate-10` | Texto placeholder/muted | Placeholders, hints |
| `text-n-ruby-11` | Vermelho (valores) | Dívidas, valores negativos |

---

## 5. Padrões de layout de página

### Wrapper de página
```html
<section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
  <!-- sticky header -->
  <header class="sticky top-0 z-10 bg-n-surface-1 border-b border-n-weak px-6 shrink-0">
    ...
  </header>
  <!-- scrollable content -->
  <main class="flex-1 px-6 overflow-y-auto">
    <div class="w-full max-w-5xl mx-auto py-5 flex flex-col gap-5">
      ...
    </div>
  </main>
</section>
```

### Card
```html
<div class="outline outline-1 outline-n-container -outline-offset-1 rounded-xl bg-n-solid-2 overflow-hidden">
  ...
</div>
```

### Tipografia de página
```html
<h1 class="text-xl font-medium text-n-slate-12">Título</h1>
<p class="text-sm text-n-slate-11">Descrição</p>
```

---

## 6. Playwright — instalação global

Para instalar o Playwright globalmente e usar fora do projeto:

```bash
npm install -g playwright
npx playwright install chromium
```

Ou via `@playwright/test` (inclui test runner):
```bash
npm install -g @playwright/test
npx playwright install chromium
```

### Atenção: login no Chatwoot via Playwright
O campo de email do Chatwoot pode não estar disponível imediatamente. Usar:
- `waitUntil: 'domcontentloaded'` + `waitForSelector('input')` com timeout maior (15s+)
- Após submit, aguardar a URL mudar para `/dashboard` antes de prosseguir
- `setDefaultTimeout(15000)` no início do script
