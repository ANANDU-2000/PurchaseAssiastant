# Bug #6 Fix: AI Field Mismatch
# Map all rate aliases to single landing_cost field

from typing import Dict, Any, List, Optional

class EntityFieldResolver:
    """
    Resolve all field aliases to canonical field names.
    Maps multiple rate field names to single 'landing_cost' field.
    """
    
    # Field alias mappings
    FIELD_ALIASES = {
        'landing_cost': ['landing_cost', 'land', 'landing', 'lc', 'purchase_rate', 'purchase_price', 'buy_price', 'bp', 'rate', 'price', 'cost', 'unit_rate'],
        'qty': ['qty', 'quantity', 'q', 'amount'],
        'item_name': ['item_name', 'item', 'product', 'goods'],
        'supplier_id': ['supplier_id', 'supplier', 'vendor'],
        'unit': ['unit', 'u', 'measure'],
    }
    
    @staticmethod
    def resolve_entity_fields(parsed_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Resolve all field aliases to canonical field names.
        """
        resolved = {}
        
        for canonical_field, aliases in EntityFieldResolver.FIELD_ALIASES.items():
            for key, value in parsed_data.items():
                if key.lower() in [a.lower() for a in aliases]:
                    # Special handling for rate fields - only set once
                    if canonical_field == 'landing_cost' and 'landing_cost' not in resolved:
                        resolved['landing_cost'] = value
                    elif canonical_field != 'landing_cost':
                        resolved[canonical_field] = value
                    break
        
        return resolved
    
    @staticmethod
    def build_entry_create_request(entity_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Build purchase entry create request from entity data.
        Only requires landing_cost (not separate buy_price).
        """
        
        # Resolve field aliases
        resolved = EntityFieldResolver.resolve_entity_fields(entity_data)
        
        # Validate required fields
        required_fields = ['item_name', 'qty', 'landing_cost']
        missing = [f for f in required_fields if f not in resolved or not resolved[f]]
        
        if missing:
            return {
                'error': f'Missing required fields: {", ".join(missing)}',
                'missing_fields': missing,
            }
        
        # Build request
        return {
            'item_name': resolved.get('item_name'),
            'qty': float(resolved.get('qty', 0)),
            'landing_cost': float(resolved.get('landing_cost', 0)),
            'unit': resolved.get('unit', 'kg'),
            'supplier_id': resolved.get('supplier_id'),
        }


class PurchaseEntity:
    """
    AI-assisted purchase entry entity.
    Maps user input to purchase fields.
    """
    
    def __init__(self):
        self.item_name: Optional[str] = None
        self.qty: Optional[float] = None
        self.landing_cost: Optional[float] = None  # Single rate field (not buy_price)
        self.unit: str = 'kg'
        self.supplier_id: Optional[str] = None
    
    def parse_user_input(self, text: str) -> Dict[str, Any]:
        """
        Parse user input and extract entity fields.
        All rate mentions map to landing_cost.
        """
        
        parsed = {}
        words = text.lower().split()
        
        for field, aliases in EntityFieldResolver.FIELD_ALIASES.items():
            for word in words:
                if word in aliases:
                    # Extract value based on field type
                    if field == 'qty':
                        # Find number before quantity keyword
                        try:
                            idx = words.index(word)
                            if idx > 0 and words[idx-1].replace('.', '').isdigit():
                                parsed[field] = float(words[idx-1])
                        except (ValueError, IndexError):
                            pass
                    
                    elif field == 'landing_cost':
                        # Find number after rate keyword
                        try:
                            idx = words.index(word)
                            if idx < len(words) - 1 and words[idx+1].replace('.', '').isdigit():
                                parsed[field] = float(words[idx+1])
                        except (ValueError, IndexError):
                            pass
                    
                    elif field in ['item_name', 'unit', 'supplier_id']:
                        parsed[field] = word
        
        return parsed
    
    def get_missing_fields(self) -> List[str]:
        """Get list of required fields that are still missing."""
        
        required = ['item_name', 'qty', 'landing_cost']
        missing = []
        
        for field in required:
            value = getattr(self, field, None)
            if value is None or (isinstance(value, str) and not value.strip()):
                missing.append(field)
        
        return missing
    
    def get_ai_system_prompt(self) -> str:
        """
        Generate AI system prompt with collected fields.
        Only asks for missing required fields.
        """
        
        collected = []
        if self.item_name:
            collected.append(f"Item: {self.item_name}")
        if self.qty:
            collected.append(f"Quantity: {self.qty} {self.unit}")
        if self.landing_cost:
            collected.append(f"Rate: ₹{self.landing_cost}/unit")
        if self.supplier_id:
            collected.append(f"Supplier: {self.supplier_id}")
        
        missing = self.get_missing_fields()
        
        prompt = "You are helping create a purchase entry.\n\n"
        
        if collected:
            prompt += "Fields collected so far:\n"
            prompt += "\n".join(f"- {c}" for c in collected)
            prompt += "\n\n"
        
        if missing:
            prompt += f"Still need: {', '.join(missing)}\n"
            prompt += "Ask for the next missing field clearly.\n"
        else:
            prompt += "All required fields collected. Confirm the entry or ask for corrections.\n"
        
        prompt += "\nImportant: Only ask for ONE field at a time."
        prompt += "\nDo NOT ask for 'buy price' and 'landing cost' separately - they are the same."
        prompt += "\nUse 'rate' or 'price' when asking for the cost per unit."
        
        return prompt
