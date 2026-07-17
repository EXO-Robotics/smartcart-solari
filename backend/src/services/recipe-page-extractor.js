import { RecipePageError } from './recipe-page-fetcher.js';

const VOID_TAGS = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const IGNORED_TAGS = new Set(['script', 'style', 'noscript', 'template', 'svg']);
const STOP_HEADING = /^(instructions?|directions?|method|preparation|steps?|equipment|notes?|nutrition|frequently asked questions|faq)\b/i;
const INGREDIENT_HEADING = /^ingredients?\b/i;

function decodeEntities(value) {
  const named = {
    amp: '&', apos: "'", gt: '>', lt: '<', nbsp: ' ', quot: '"',
    frac12: '½', frac13: '⅓', frac14: '¼', frac23: '⅔', frac34: '¾',
    ndash: '–', mdash: '—', times: '×'
  };
  return value.replace(/&(#(?:x[0-9a-f]+|\d+)|[a-z][a-z0-9]+);?/gi, (match, entity) => {
    if (entity[0] === '#') {
      const hex = entity[1]?.toLowerCase() === 'x';
      const codePoint = Number.parseInt(entity.slice(hex ? 2 : 1), hex ? 16 : 10);
      if (Number.isInteger(codePoint) && codePoint > 0 && codePoint <= 0x10ffff) {
        try { return String.fromCodePoint(codePoint); } catch { return match; }
      }
      return match;
    }
    return named[entity.toLowerCase()] ?? match;
  });
}

function cleanText(value) {
  return decodeEntities(value).replace(/[\t\r\n ]+/g, ' ').trim();
}

function parseAttributes(source) {
  const attributes = {};
  const expression = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  for (const match of source.matchAll(expression)) {
    attributes[match[1].toLowerCase()] = decodeEntities(match[2] ?? match[3] ?? match[4] ?? '');
  }
  return attributes;
}

function parseHtml(html) {
  const root = { tag: '#document', attrs: {}, children: [], parent: null };
  const stack = [root];
  const expression = /<!--[\s\S]*?-->|<![^>]*>|<\/?[A-Za-z][^>]*>|[^<]+|</g;
  for (const match of html.matchAll(expression)) {
    const token = match[0];
    if (!token || token.startsWith('<!--') || token.startsWith('<!')) continue;
    if (!token.startsWith('<')) {
      stack.at(-1).children.push({ tag: '#text', text: token, parent: stack.at(-1) });
      continue;
    }
    const closing = /^<\//.test(token);
    const name = /^<\/?\s*([A-Za-z][\w:-]*)/.exec(token)?.[1].toLowerCase();
    if (!name) continue;
    if (closing) {
      for (let index = stack.length - 1; index > 0; index -= 1) {
        if (stack[index].tag === name) {
          stack.length = index;
          break;
        }
      }
      continue;
    }
    const attributeSource = token.slice(token.indexOf(name) + name.length, token.lastIndexOf('>'));
    const node = { tag: name, attrs: parseAttributes(attributeSource), children: [], parent: stack.at(-1) };
    stack.at(-1).children.push(node);
    if (!VOID_TAGS.has(name) && !/\/\s*>$/.test(token)) stack.push(node);
  }
  return root;
}

function nodeText(node) {
  if (node.tag === '#text') return node.text;
  if (IGNORED_TAGS.has(node.tag)) return '';
  return cleanText(node.children.map(nodeText).join(' '));
}

function walk(node, output = []) {
  if (node.tag !== '#text') output.push(node);
  for (const child of node.children ?? []) walk(child, output);
  return output;
}

function attrTokens(node, name) {
  return (node.attrs[name] ?? '').toLowerCase().split(/\s+/).filter(Boolean);
}

function hasRecipeType(value) {
  const types = Array.isArray(value) ? value : [value];
  return types.some((type) => typeof type === 'string' && /(^|[/:#])recipe$/i.test(type.trim()));
}

function ingredientStrings(value) {
  if (typeof value === 'string') return cleanText(value) ? [cleanText(value)] : [];
  if (Array.isArray(value)) return value.flatMap(ingredientStrings);
  if (!value || typeof value !== 'object') return [];
  const nested = value.itemListElement ?? value.recipeIngredient ?? value.ingredients;
  if (nested !== undefined) return ingredientStrings(nested);
  if (typeof value.text === 'string') return ingredientStrings(value.text);
  if (typeof value.name === 'string') return ingredientStrings(value.name);
  return [];
}

function jsonLdCandidates(value, output = []) {
  if (Array.isArray(value)) {
    for (const item of value) jsonLdCandidates(item, output);
  } else if (value && typeof value === 'object') {
    if (hasRecipeType(value['@type'])) output.push(value);
    for (const nested of Object.values(value)) jsonLdCandidates(nested, output);
  }
  return output;
}

function sectionsFromJsonLd(recipe, ingredients) {
  const value = recipe.recipeIngredient ?? recipe.ingredients;
  if (!Array.isArray(value) || !value.some((item) => item && typeof item === 'object' && !Array.isArray(item))) {
    return [{ name: null, ingredients }];
  }
  const sections = [];
  for (const item of value) {
    if (typeof item === 'string') {
      if (!sections.length) sections.push({ name: null, ingredients: [] });
      sections.at(-1).ingredients.push(cleanText(item));
      continue;
    }
    const sectionIngredients = ingredientStrings(item.itemListElement ?? item.recipeIngredient ?? item.ingredients);
    if (sectionIngredients.length) sections.push({ name: cleanText(item.name ?? '') || null, ingredients: sectionIngredients });
  }
  return sections.length ? sections : [{ name: null, ingredients }];
}

function extractJsonLd(html) {
  const candidates = [];
  const expression = /<script\b[^>]*\btype\s*=\s*(?:["']application\/ld\+json["']|application\/ld\+json)[^>]*>([\s\S]*?)<\/script\s*>/gi;
  let order = 0;
  for (const match of html.matchAll(expression)) {
    let parsed;
    try {
      parsed = JSON.parse(match[1].replace(/^\s*<!--|-->\s*$/g, '').trim());
    } catch {
      try { parsed = JSON.parse(decodeEntities(match[1]).trim()); } catch { continue; }
    }
    for (const recipe of jsonLdCandidates(parsed)) {
      const ingredients = ingredientStrings(recipe.recipeIngredient ?? recipe.ingredients);
      if (ingredients.length) candidates.push({ recipe, ingredients, order: order++ });
    }
  }
  candidates.sort((left, right) => right.ingredients.length - left.ingredients.length || left.order - right.order);
  const selected = candidates[0];
  if (!selected) return null;
  return {
    name: cleanText(selected.recipe.name ?? '') || 'Imported Recipe',
    ingredients: selected.ingredients,
    ingredientSections: sectionsFromJsonLd(selected.recipe, selected.ingredients),
    extractionMethod: 'json-ld'
  };
}

function nearestRecipeName(nodes) {
  const title = nodes.find((node) => node.tag === 'h1' && nodeText(node));
  return title ? nodeText(title) : 'Imported Recipe';
}

function normalizeSections(sections) {
  const normalized = sections
    .map((section) => ({
      name: section.name ? cleanText(section.name) : null,
      ingredients: section.ingredients.map(cleanText).filter(Boolean)
    }))
    .filter((section) => section.ingredients.length);
  const ingredients = normalized.flatMap((section) => section.ingredients);
  return { ingredients, ingredientSections: normalized };
}

function sectionedIngredients(nodes, { startIndex = 0, stopAtBoundary = false, headingLevel = 2 } = {}) {
  const sections = [];
  const seen = new Set();
  let current = { name: null, ingredients: [] };
  const flush = () => {
    if (current.ingredients.length) sections.push(current);
    current = { name: null, ingredients: [] };
  };

  for (let index = startIndex; index < nodes.length; index += 1) {
    const node = nodes[index];
    if (/^h[1-6]$/.test(node.tag)) {
      const text = nodeText(node);
      const level = Number(node.tag[1]);
      if (stopAtBoundary && STOP_HEADING.test(text) && level <= headingLevel) break;
      if (!INGREDIENT_HEADING.test(text) && !STOP_HEADING.test(text)) {
        flush();
        current.name = text || null;
      }
      continue;
    }

    if (node.tag !== 'li') continue;
    if (node.parent?.tag === 'li') continue;
    const text = nodeText(node);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    current.ingredients.push(text);
  }
  flush();
  return normalizeSections(sections);
}

function extractMicrodata(allNodes) {
  const ingredientNodes = allNodes.filter((node) => attrTokens(node, 'itemprop').includes('recipeingredient'));
  if (!ingredientNodes.length) return null;
  const sections = [];
  let current = { name: null, ingredients: [] };
  for (const node of ingredientNodes) {
    const text = nodeText(node);
    if (!text) continue;
    let sectionName = null;
    let sibling = node;
    while (sibling.parent && !sectionName) {
      const siblings = sibling.parent.children;
      const index = siblings.indexOf(sibling);
      for (let previous = index - 1; previous >= 0; previous -= 1) {
        if (/^h[2-6]$/.test(siblings[previous].tag)) {
          const heading = nodeText(siblings[previous]);
          if (!INGREDIENT_HEADING.test(heading)) sectionName = heading;
          break;
        }
      }
      sibling = sibling.parent;
    }
    if (sectionName !== current.name && current.ingredients.length) {
      sections.push(current);
      current = { name: sectionName, ingredients: [] };
    } else if (!current.ingredients.length) {
      current.name = sectionName;
    }
    current.ingredients.push(text);
  }
  if (current.ingredients.length) sections.push(current);
  const normalized = normalizeSections(sections);
  if (!normalized.ingredients.length) return null;
  return {
    name: nearestRecipeName(allNodes),
    ...normalized,
    extractionMethod: 'microdata'
  };
}

function extractPlugin(allNodes) {
  const containers = allNodes.filter((node) => {
    const marker = `${node.attrs.id ?? ''} ${node.attrs.class ?? ''}`.toLowerCase();
    return /(?:wprm|tasty-recipes|mv-create|recipe)[-_ ]ingredients(?:[-_ ]container)?/.test(marker);
  });
  const candidates = [];
  for (const container of containers) {
    const nodes = walk(container, []);
    const ingredientHeading = nodes.find((node) => /^h[1-6]$/.test(node.tag) && INGREDIENT_HEADING.test(nodeText(node)));
    const extracted = sectionedIngredients(nodes, {
      stopAtBoundary: true,
      headingLevel: ingredientHeading ? Number(ingredientHeading.tag[1]) : 2
    });
    if (extracted.ingredients.length) candidates.push(extracted);
  }
  candidates.sort((left, right) => right.ingredients.length - left.ingredients.length);
  if (!candidates.length) return null;
  return {
    name: nearestRecipeName(allNodes),
    ...candidates[0],
    extractionMethod: 'plugin'
  };
}

function extractVisible(allNodes) {
  for (let index = 0; index < allNodes.length; index += 1) {
    const heading = allNodes[index];
    if (!/^h[1-6]$/.test(heading.tag) || !INGREDIENT_HEADING.test(nodeText(heading))) continue;
    const extracted = sectionedIngredients(allNodes, {
      startIndex: index + 1,
      stopAtBoundary: true,
      headingLevel: Number(heading.tag[1])
    });
    if (extracted.ingredients.length) {
      return {
        name: nearestRecipeName(allNodes),
        ...extracted,
        extractionMethod: 'visible'
      };
    }
  }
  return null;
}

export class RecipePageExtractor {
  extract(html) {
    if (typeof html !== 'string' || !html.trim()) {
      throw new RecipePageError(422, 'recipe_not_found', 'Recipe page did not contain extractable ingredients');
    }
    const jsonLd = extractJsonLd(html);
    if (jsonLd) return jsonLd;

    const root = parseHtml(html);
    const allNodes = walk(root, []);
    const fallback = extractMicrodata(allNodes) ?? extractPlugin(allNodes) ?? extractVisible(allNodes);
    if (fallback?.ingredients.length) return fallback;
    throw new RecipePageError(422, 'recipe_not_found', 'Recipe page did not contain extractable ingredients');
  }
}
