# Bug #7 Fix: AI Context Loss Between Turns
# Persist entity draft in Redis with TTL

import json
import redis
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

class WhatsAppEntityDraft:
    """
    Manages entity draft persistence for WhatsApp conversations.
    Stores partial purchase entry data between turns.
    """
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.draft_ttl = 1800  # 30 minutes
    
    def get_draft_key(self, phone: str) -> str:
        """Get Redis key for entity draft."""
        return f"whatsapp:draft:{phone}"
    
    def save_draft(self, phone: str, entity_data: Dict[str, Any]) -> bool:
        """
        Save entity draft to Redis.
        Persists partial purchase entry data.
        """
        try:
            key = self.get_draft_key(phone)
            draft_json = json.dumps(entity_data)
            
            # Set with TTL (30 minutes)
            self.redis.setex(
                key,
                self.draft_ttl,
                draft_json
            )
            
            return True
        except Exception as e:
            print(f"Error saving draft: {e}")
            return False
    
    def load_draft(self, phone: str) -> Optional[Dict[str, Any]]:
        """
        Load entity draft from Redis.
        Returns None if draft expired or not found.
        """
        try:
            key = self.get_draft_key(phone)
            draft_json = self.redis.get(key)
            
            if not draft_json:
                return None
            
            return json.loads(draft_json)
        except Exception as e:
            print(f"Error loading draft: {e}")
            return None
    
    def merge_draft(self, phone: str, new_fields: Dict[str, Any]) -> Dict[str, Any]:
        """
        Merge new fields into existing draft.
        Preserves previously collected fields.
        """
        # Load existing draft
        existing = self.load_draft(phone) or {}
        
        # Merge new fields (don't overwrite existing unless explicitly set)
        merged = {**existing}
        
        for key, value in new_fields.items():
            if value is not None and value != '':
                merged[key] = value
        
        # Save merged draft
        self.save_draft(phone, merged)
        
        return merged
    
    def clear_draft(self, phone: str) -> bool:
        """Clear entity draft after successful save."""
        try:
            key = self.get_draft_key(phone)
            self.redis.delete(key)
            return True
        except Exception as e:
            print(f"Error clearing draft: {e}")
            return False
    
    def get_collected_fields(self, phone: str) -> Dict[str, Any]:
        """Get all fields collected so far."""
        return self.load_draft(phone) or {}


class EntityResolutionWithContext:
    """
    Resolve entity fields with context from previous turns.
    Maintains conversation history and draft state.
    """
    
    def __init__(self, draft_manager: WhatsAppEntityDraft):
        self.draft = draft_manager
    
    def resolve_with_context(
        self,
        phone: str,
        new_input: str,
        parsed_fields: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Resolve fields with context from previous turns.
        Merges new parsed fields into existing draft.
        """
        
        # Load existing draft
        existing_fields = self.draft.load_draft(phone) or {}
        
        # Merge new fields (new fields override old ones)
        merged = {**existing_fields, **parsed_fields}
        
        # Save merged draft
        self.draft.save_draft(phone, merged)
        
        return merged
    
    def get_missing_fields(
        self,
        phone: str,
        required_fields: list
    ) -> list:
        """Get list of required fields still missing."""
        
        collected = self.draft.get_collected_fields(phone)
        missing = []
        
        for field in required_fields:
            if field not in collected or not collected[field]:
                missing.append(field)
        
        return missing
    
    def get_conversation_context(self, phone: str) -> str:
        """
        Get formatted context string for AI system prompt.
        Shows all fields collected so far.
        """
        
        collected = self.draft.get_collected_fields(phone)
        
        if not collected:
            return "No fields collected yet."
        
        context_lines = ["Fields collected so far:"]
        
        for key, value in collected.items():
            if value:
                # Format field name
                field_name = key.replace('_', ' ').title()
                context_lines.append(f"- {field_name}: {value}")
        
        return "\n".join(context_lines)


# Example usage in WhatsApp handler:

async def handle_whatsapp_message_with_context(
    phone: str,
    message_text: str,
    draft_manager: WhatsAppEntityDraft,
    entity_resolver: EntityResolutionWithContext,
) -> str:
    """
    Handle WhatsApp message with context persistence.
    """
    
    # Parse user input (implement based on your NLP)
    # parsed_fields = parse_user_input(message_text)
    
    # Resolve with context (merge into draft)
    # current_fields = entity_resolver.resolve_with_context(
    #     phone,
    #     message_text,
    #     parsed_fields
    # )
    
    # Get missing required fields
    required = ['item_name', 'qty', 'landing_cost']
    # missing = entity_resolver.get_missing_fields(phone, required)
    
    # Build AI system prompt with context
    context = entity_resolver.get_conversation_context(phone)
    
    system_prompt = f"""You are helping create a purchase entry.

{context}

Required fields still needed: {', '.join(['item_name', 'qty', 'landing_cost']) if True else 'None - ready to save'}

Instructions:
1. Only ask for ONE missing field at a time
2. Be conversational and helpful
3. Don't ask for fields that are already collected
4. When all fields are collected, ask for confirmation
5. Never ask for 'buy price' and 'landing cost' separately

Current turn: Ask for the next missing field or confirm if complete."""
    
    # Get AI response (implement based on your LLM)
    # ai_response = await ai_service.generate_response(
    #     system_prompt=system_prompt,
    #     user_message=message_text,
    # )
    
    # return ai_response
    return system_prompt
