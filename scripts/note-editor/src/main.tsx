// Notes editor of Matcha (task 12.2): OpenBlock and its React menus, in the page served by `NoteEditorSchemeHandler`.
// The app drives it through the bridge of its own content world (`NoteEditorScript`), by DOM events whose detail is
// JSON text: this page never talks to the app directly (review WB2).
import { useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { DEFAULT_NODES, getDefaultSlashMenuItems, type Block, type SlashMenuItem } from '@labbs/openblock-core';
import {
  BUBBLE_MENU_ITEMS,
  BubbleMenu,
  DEFAULT_BUBBLE_MENU_ORDER,
  OpenBlockView,
  SlashMenu,
  TableHandles,
  useOpenBlock,
  type BubbleMenuItem,
} from '@labbs/openblock-react';
import './editor.css';

/** Events shared with the bridge script (`NoteEditorScript.events`). */
const EVENTS = {
  ready: 'matcha-note-ready',
  load: 'matcha-note-load',
  change: 'matcha-note-change',
  flush: 'matcha-note-flush',
  unreadable: 'matcha-note-unreadable',
};
/** Quiet time after the last change before the document leaves for the app. */
const SAVE_DELAY = 400;
/** Blocks left out of the menu: no network and no attachments yet. */
const HIDDEN_ITEMS = new Set(['image', 'embed']);
const KNOWN_BLOCKS = new Set(Object.keys(DEFAULT_NODES));
const KNOWN_INLINE = new Set(['text', 'link', 'hardBreak']);
const MAXIMUM_DEPTH = 64;

/** A note given by the app: its document, whether it can be changed, and the texts of the menus. */
interface Session {
  token: string;
  blocks: Block[];
  editable: boolean;
  texts: Record<string, string>;
}

function send(name: string, detail: object): void {
  document.dispatchEvent(new CustomEvent(name, { detail: JSON.stringify(detail) }));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isReadableInline(item: unknown): boolean {
  return isRecord(item) && typeof item.type === 'string' && KNOWN_INLINE.has(item.type);
}

/** True if every block, at every level, is one this editor knows: an unknown one would silently become a paragraph. */
function isReadableBlock(block: unknown, depth: number): boolean {
  if (depth > MAXIMUM_DEPTH || !isRecord(block) || typeof block.type !== 'string' || !KNOWN_BLOCKS.has(block.type)) {
    return false;
  }
  const { content, children } = block;
  if (content !== undefined && !(Array.isArray(content) && content.every(isReadableInline))) {
    return false;
  }
  return children === undefined || (Array.isArray(children) && children.every((child) => isReadableBlock(child, depth + 1)));
}

/** The blocks of `content`, or null if this editor can't read them all. */
function readBlocks(content: string): Block[] | null {
  try {
    const value: unknown = JSON.parse(content);
    return Array.isArray(value) && value.every((block) => isReadableBlock(block, 0)) ? (value as Block[]) : null;
  } catch {
    return null;
  }
}

/** The default items, in the app's language, without the hidden ones. */
function translatedSlashItems(items: SlashMenuItem[], texts: Record<string, string>): SlashMenuItem[] {
  return items
    .filter((item) => !HIDDEN_ITEMS.has(item.id))
    .map((item) => ({
      ...item,
      title: texts[`slash.${item.id}.title`] ?? item.title,
      description: texts[`slash.${item.id}.description`] ?? item.description,
      group: (item.group && texts[`slash.group.${item.group}`]) ?? item.group,
      // The English title still finds the item.
      keywords: [...(item.keywords ?? []), item.title],
    }));
}

function translatedBubbleItems(texts: Record<string, string>): BubbleMenuItem[] {
  return Object.values(BUBBLE_MENU_ITEMS).map((item) => ({ ...item, label: texts[`bubble.${item.id}`] ?? item.label }));
}

function NoteEditor({ session }: { session: Session }) {
  const dirty = useRef(false);
  const timer = useRef<number | undefined>(undefined);
  const editor = useOpenBlock({
    initialContent: session.blocks,
    editable: session.editable,
    placeholder: session.texts.placeholder,
    onUpdate: () => {
      if (!session.editable) {
        return;
      }
      dirty.current = true;
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(emit, SAVE_DELAY);
    },
    onBlur: () => emit(),
  });
  const editorRef = useRef(editor);
  editorRef.current = editor;

  function emit(): void {
    window.clearTimeout(timer.current);
    const current = editorRef.current;
    if (!dirty.current || !current) {
      return;
    }
    dirty.current = false;
    send(EVENTS.change, { token: session.token, content: JSON.stringify(current.getDocument()) });
  }

  useEffect(() => {
    // The app asks for the document before showing another note or closing the panel: answered at once.
    const flush = () => emit();
    document.addEventListener(EVENTS.flush, flush);
    return () => {
      document.removeEventListener(EVENTS.flush, flush);
      emit();
    };
  }, []);

  const slashItems = useMemo(
    () => (editor ? translatedSlashItems(getDefaultSlashMenuItems(editor.pm.state.schema), session.texts) : []),
    [editor, session.texts],
  );
  const bubbleItems = useMemo(() => translatedBubbleItems(session.texts), [session.texts]);

  return (
    <>
      <OpenBlockView editor={editor} />
      {session.editable && (
        <>
          <SlashMenu editor={editor} items={slashItems} />
          <BubbleMenu editor={editor} customItems={bubbleItems} itemOrder={DEFAULT_BUBBLE_MENU_ORDER} />
          <TableHandles editor={editor} />
        </>
      )}
    </>
  );
}

function App() {
  const [session, setSession] = useState<Session | null>(null);

  useEffect(() => {
    const load = (event: Event) => {
      const detail = JSON.parse(String((event as CustomEvent).detail));
      const blocks = readBlocks(String(detail.content));
      if (!blocks) {
        send(EVENTS.unreadable, { token: detail.token });
      }
      setSession({
        token: String(detail.token),
        blocks: blocks ?? [],
        editable: blocks !== null && detail.editable === true,
        texts: isRecord(detail.texts) ? (detail.texts as Record<string, string>) : {},
      });
    };
    document.addEventListener(EVENTS.load, load);
    send(EVENTS.ready, {});
    return () => document.removeEventListener(EVENTS.load, load);
  }, []);

  // A new editor for each note: its undo history starts empty.
  return session ? <NoteEditor key={session.token} session={session} /> : null;
}

const root = document.getElementById('root');
if (root) {
  createRoot(root).render(<App />);
}
